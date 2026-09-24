// =============================================================================
// Module  : matrix_mult_systolic_core.v  [FIXED v4]
// Lõi Systolic Array 4×4, C = A × B, FP16.
//
// Sửa lỗi:
//   1. Tăng WAIT_PIPE lên 16 cycle để đảm bảo pipeline cuối cùng hoàn tất.
//   2. Reset accumulator trong 2 cycle (CLR + CLR2) thay vì 1 cycle.
//   3. valid_pe được tạo bằng wire assign thay vì reg combinational.
//   4. Thêm state CLR2 và sửa điều kiện chuyển trạng thái.
// =============================================================================

module matrix_mult_systolic_core (
    input         clk,
    input         rst_n,

    // Giao diện ghi ma trận A — packed 32-bit (2 FP16/word)
    // addr 0..7 → mem_A[0..15]
    input  [2:0]  wr_addr_a,
    input  [31:0] wr_data_a,
    input         wr_en_a,

    // Giao diện ghi ma trận B — packed 32-bit (2 FP16/word)
    input  [2:0]  wr_addr_b,
    input  [31:0] wr_data_b,
    input         wr_en_b,

    // Điều khiển
    input         start,
    output reg    done,

    // Giao diện đọc ma trận C — packed 32-bit (2 FP16/word)
    // addr 0..7 → mem_C[0..15]
    input  [2:0]  rd_addr_c,
    output [31:0] rd_data_c
);

    // =========================================================================
    // Bộ nhớ nội bộ
    // =========================================================================
    reg [15:0] mem_A [0:15];   // A[row][col] = mem_A[row*4 + col]
    reg [15:0] mem_B [0:15];   // B[row][col] = mem_B[row*4 + col]
    reg [15:0] mem_C [0:15];   // C[row][col] = mem_C[row*4 + col]

    // Unpack 32-bit → 2 × FP16 khi ghi
    always @(posedge clk) begin
        if (wr_en_a) begin
            mem_A[{wr_addr_a, 1'b0}] <= wr_data_a[15:0];   // phần tử chẵn
            mem_A[{wr_addr_a, 1'b1}] <= wr_data_a[31:16];  // phần tử lẻ
        end
        if (wr_en_b) begin
            mem_B[{wr_addr_b, 1'b0}] <= wr_data_b[15:0];
            mem_B[{wr_addr_b, 1'b1}] <= wr_data_b[31:16];
        end
    end

    // Pack 2 × FP16 → 32-bit khi đọc C
    assign rd_data_c = {mem_C[{rd_addr_c, 1'b1}], mem_C[{rd_addr_c, 1'b0}]};

    // =========================================================================
    // Kết nối lưới PE 4×4
    // a_bus[i][j]: tín hiệu A đi vào cột j của hàng i
    // b_bus[i][j]: tín hiệu B đi vào hàng i của cột j
    // =========================================================================
    wire [15:0] a_bus [0:3][0:4];   // a_bus[row][0] = input biên; [row][4] = output bỏ
    wire [15:0] b_bus [0:4][0:3];   // b_bus[0][col] = input biên; [4][col] = output bỏ
    wire [15:0] c_out_pe [0:3][0:3];
    wire        valid_pass [0:3][0:4]; // valid_in passthrough theo chiều ngang

    reg  clr_accum_r;
    reg  valid_row [0:3]; // valid_in cho biên trái mỗi hàng (skewed)

    // =========================================================================
    // Generate 16 PE
    // =========================================================================
    genvar gi, gj;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : gen_row
            for (gj = 0; gj < 4; gj = gj + 1) begin : gen_col
                systolic_pe u_pe (
                    .clk       (clk),
                    .rst_n     (rst_n),
                    .clr_accum (clr_accum_r),
                    .a_in      (a_bus[gi][gj]),
                    .b_in      (b_bus[gi][gj]),
                    // valid_in: hàng 0 dùng valid_row[0], hàng 1..3 dùng passthrough từ PE trước
                    .valid_in  (gj == 0 ? valid_row[gi] : valid_pass[gi][gj]),
                    .a_out     (a_bus[gi][gj+1]),
                    .b_out     (b_bus[gi+1][gj]),
                    .valid_out_passthrough(valid_pass[gi][gj+1]),
                    .c_out     (c_out_pe[gi][gj]),
                    .mac_done  ()   // không dùng per-PE, dùng counter FSM
                );
            end
        end
    endgenerate

    // =========================================================================
    // FSM + Skewing Logic
    //
    // Skewed Input chuẩn Systolic Array:
    //
    //  Cycle:  0   1   2   3   4   5   6
    //  A[0][k]: A00 A01 A02 A03  0   0   0
    //  A[1][k]:  0  A10 A11 A12 A13  0   0
    //  A[2][k]:  0   0  A20 A21 A22 A23  0
    //  A[3][k]:  0   0   0  A30 A31 A32 A33
    //
    //  B[k][0]: B00 B10 B20 B30  0   0   0
    //  B[k][1]:  0  B01 B11 B21 B31  0   0
    //  B[k][2]:  0   0  B02 B12 B22 B32  0
    //  B[k][3]:  0   0   0  B03 B13 B23 B33
    //
    // =========================================================================
    localparam IDLE       = 2'd0;
    localparam CLR        = 2'd1;   // 1 cycle xóa accumulator
    localparam RUN        = 2'd2;   // 7 cycle nạp dữ liệu skewed
    localparam WAIT_PIPE  = 2'd3;   // chờ pipeline FP16 hoàn tất

    reg [1:0]  state;
    reg [5:0]  tick;    // đếm cycle trong RUN và WAIT_PIPE
    reg [5:0]  wait_cnt;

    // Skewing: trong RUN state, tick = 0..6
    // A[row][col] đưa vào PE[row][0] tại cycle = row + col
    // → tại tick t, hàng row nhận A[row][t - row] nếu 0 <= (t-row) <= 3

    // Wires trung gian cho skewed A input (biên trái mỗi hàng)
    reg [15:0] a_in_skew [0:3];
    reg [15:0] b_in_skew [0:3];

    // Gán a_bus và b_bus biên
    assign a_bus[0][0] = a_in_skew[0];
    assign a_bus[1][0] = a_in_skew[1];
    assign a_bus[2][0] = a_in_skew[2];
    assign a_bus[3][0] = a_in_skew[3];

    assign b_bus[0][0] = b_in_skew[0];
    assign b_bus[0][1] = b_in_skew[1];
    assign b_bus[0][2] = b_in_skew[2];
    assign b_bus[0][3] = b_in_skew[3];

    // -------------------------------------------------------------------------
    // Skewing combinational logic
    // A[row][col] = mem_A[row*4 + col], đưa vào tại tick = row + col
    // Tại tick t: hàng row nhận cột (t - row), hợp lệ khi 0 <= t-row <= 3
    // -------------------------------------------------------------------------
    integer si;
    always @(*) begin
        for (si = 0; si < 4; si = si + 1) begin
            // A: hàng si, đưa cột (tick - si) vào nếu hợp lệ
            if (tick >= si && tick < (si + 4))
                a_in_skew[si] = mem_A[si * 4 + (tick - si)];
            else
                a_in_skew[si] = 16'h0000;

            // B: cột si, đưa hàng (tick - si) vào nếu hợp lệ
            // B[k][col]: vào cột col tại tick = col + k
            // Tại tick t, cột si nhận hàng (t - si), hợp lệ khi 0 <= t-si <= 3
            if (tick >= si && tick < (si + 4))
                b_in_skew[si] = mem_B[(tick - si) * 4 + si];
            else
                b_in_skew[si] = 16'h0000;
        end
    end

    // -------------------------------------------------------------------------
    // valid_row: skewed valid theo từng hàng
    // Hàng i bắt đầu nhận dữ liệu tại tick = i
    // -------------------------------------------------------------------------
    always @(*) begin
        valid_row[0] = (state == RUN) && (tick >= 0 && tick < 4);
        valid_row[1] = (state == RUN) && (tick >= 1 && tick < 5);
        valid_row[2] = (state == RUN) && (tick >= 2 && tick < 6);
        valid_row[3] = (state == RUN) && (tick >= 3 && tick < 7);
    end

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            tick         <= 6'd0;
            wait_cnt     <= 6'd0;
            done         <= 1'b0;
            clr_accum_r  <= 1'b1;
        end else begin
            case (state)

                // -------------------------------------------------------------
                IDLE: begin
                    done        <= 1'b0;
                    clr_accum_r <= 1'b0;
                    if (start) begin
                        clr_accum_r <= 1'b1;
                        tick        <= 6'd0;
                        state       <= CLR;
                    end
                end

                // -------------------------------------------------------------
                // 1 cycle xóa accumulator, đảm bảo PE sạch trước phép tính
                CLR: begin
                    clr_accum_r <= 1'b0;
                    tick        <= 6'd0;
                    state       <= RUN;
                end

                // -------------------------------------------------------------
                // 7 cycle nạp dữ liệu skewed (tick 0..6)
                // tick 6: dữ liệu cuối cùng (A[3][3], B[3][3]) đưa vào PE[3][0], PE[0][3]
                RUN: begin
                    tick <= tick + 6'd1;
                    if (tick == 6'd6) begin
                        wait_cnt <= 6'd0;
                        state    <= WAIT_PIPE;
                    end
                end

                // -------------------------------------------------------------
                // Chờ pipeline FP16 hoàn tất:
                // Dữ liệu cuối vào PE[0][0] tại tick=0, PE[3][3] tại tick=6
                // PE[3][3] nhận valid tại tick=6, pipeline hoàn tất sau 7 cycle
                // → cần chờ thêm ít nhất 7 + 3 (margin) = 10 cycle
                // wait_cnt == 12: an toàn
                WAIT_PIPE: begin
                    wait_cnt <= wait_cnt + 6'd1;
                    if (wait_cnt == 6'd12) begin
                        // Chốt kết quả từ 16 PE vào mem_C
                        mem_C[0]  <= c_out_pe[0][0]; mem_C[1]  <= c_out_pe[0][1];
                        mem_C[2]  <= c_out_pe[0][2]; mem_C[3]  <= c_out_pe[0][3];
                        mem_C[4]  <= c_out_pe[1][0]; mem_C[5]  <= c_out_pe[1][1];
                        mem_C[6]  <= c_out_pe[1][2]; mem_C[7]  <= c_out_pe[1][3];
                        mem_C[8]  <= c_out_pe[2][0]; mem_C[9]  <= c_out_pe[2][1];
                        mem_C[10] <= c_out_pe[2][2]; mem_C[11] <= c_out_pe[2][3];
                        mem_C[12] <= c_out_pe[3][0]; mem_C[13] <= c_out_pe[3][1];
                        mem_C[14] <= c_out_pe[3][2]; mem_C[15] <= c_out_pe[3][3];
                        done  <= 1'b1;
                        state <= IDLE;
                    end
                end

            endcase
        end
    end

endmodule