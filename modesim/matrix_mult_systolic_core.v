// =============================================================================
// Module  : matrix_mult_systolic_core.v  [FIXED v4]
// Lõi Systolic Array 4×4, C = A × B, FP16.
//
// S?a l?i:
//   1. Tang WAIT_PIPE lên 16 cycle d? d?m b?o pipeline cu?i cùng hoàn t?t.
//   2. Reset accumulator trong 2 cycle (CLR + CLR2) thay vì 1 cycle.
//   3. valid_pe du?c t?o b?ng wire assign thay vì reg combinational.
//   4. Thêm state CLR2 và s?a di?u ki?n chuy?n tr?ng thái.
// =============================================================================

module matrix_mult_systolic_core (
    input         clk,
    input         rst_n,

    input  [2:0]  wr_addr_a,
    input  [31:0] wr_data_a,
    input         wr_en_a,

    input  [2:0]  wr_addr_b,
    input  [31:0] wr_data_b,
    input         wr_en_b,

    input         start,
    output reg    done,

    input  [2:0]  rd_addr_c,
    output [31:0] rd_data_c
);

    // =========================================================================
    // B? nh? n?i b? (32-bit packed: [15:0]=ph?n t? ch?n, [31:16]=ph?n t? l?)
    // =========================================================================
    reg [15:0] mem_A [0:15];
    reg [15:0] mem_B [0:15];
    reg [15:0] mem_C [0:15];

    always @(posedge clk) begin
        if (wr_en_a) begin
            mem_A[{wr_addr_a, 1'b0}] <= wr_data_a[15:0];
            mem_A[{wr_addr_a, 1'b1}] <= wr_data_a[31:16];
        end
        if (wr_en_b) begin
            mem_B[{wr_addr_b, 1'b0}] <= wr_data_b[15:0];
            mem_B[{wr_addr_b, 1'b1}] <= wr_data_b[31:16];
        end
    end

    assign rd_data_c = {mem_C[{rd_addr_c, 1'b1}], mem_C[{rd_addr_c, 1'b0}]};

    localparam IDLE      = 3'd0;
    localparam CLR       = 3'd1;
    localparam CLR2      = 3'd2;
    localparam RUN       = 3'd3;
    localparam WAIT_PIPE = 3'd4;

    reg [2:0] state;
    reg [3:0] tick;      // 0..6
    reg [4:0] wait_cnt;  // 0..15
    wire valid_pe [0:3][0:3];
    // =========================================================================
    // Wiring lu?i PE 4x4
    // =========================================================================
    wire [15:0] a_bus   [0:3][0:4];
    wire [15:0] b_bus   [0:4][0:3];
    wire [15:0] c_out_pe[0:3][0:3];
    wire        nc_vp   [0:3][0:4];

    reg         clr_accum_r;
    reg [15:0] a_in_skew [0:3];
    reg [15:0] b_in_skew [0:3];

    assign a_bus[0][0] = a_in_skew[0];
    assign a_bus[1][0] = a_in_skew[1];
    assign a_bus[2][0] = a_in_skew[2];
    assign a_bus[3][0] = a_in_skew[3];

    assign b_bus[0][0] = b_in_skew[0];
    assign b_bus[0][1] = b_in_skew[1];
    assign b_bus[0][2] = b_in_skew[2];
    assign b_bus[0][3] = b_in_skew[3];

    genvar gi, gj;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : gen_row
            for (gj = 0; gj < 4; gj = gj + 1) begin : gen_col
                systolic_pe u_pe (
                    .clk                  (clk),
                    .rst_n                (rst_n),
                    .clr_accum            (clr_accum_r),
                    .a_in                 (a_bus[gi][gj]),
                    .b_in                 (b_bus[gi][gj]),
                    .valid_in             (valid_pe[gi][gj]),
                    .a_out                (a_bus[gi][gj+1]),
                    .b_out                (b_bus[gi+1][gj]),
                    .valid_out_passthrough(nc_vp[gi][gj]),
                    .c_out                (c_out_pe[gi][gj]),
                    .mac_done             ()
                );
            end
        end
    endgenerate

    // =========================================================================
    // valid_pe dùng wire assign (combinational)
    // =========================================================================
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : gen_valid_row
            for (gj = 0; gj < 4; gj = gj + 1) begin : gen_valid_col
                assign valid_pe[gi][gj] = (state == RUN) &&
                                          (tick >= (gi + gj)) &&
                                          (tick < (gi + gj + 4));
            end
        end
    endgenerate

    // =========================================================================
    // FSM v?i reset 2 cycle và wait pipe d? dài
    // =========================================================================

    // -------------------------------------------------------------------------
    // Skewing: d?c d? li?u t? mem_A, mem_B theo tick
    // -------------------------------------------------------------------------
    integer sk;
    always @(*) begin
        for (sk = 0; sk < 4; sk = sk + 1) begin
            if (state == RUN && tick >= sk && tick < (sk + 4)) begin
                a_in_skew[sk] = mem_A[sk * 4 + (tick - sk)];
                b_in_skew[sk] = mem_B[(tick - sk) * 4 + sk];
            end else begin
                a_in_skew[sk] = 16'h0000;
                b_in_skew[sk] = 16'h0000;
            end
        end
    end

    // -------------------------------------------------------------------------
    // FSM sequential
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            tick        <= 4'd0;
            wait_cnt    <= 5'd0;
            done        <= 1'b0;
            clr_accum_r <= 1'b1;
        end else begin
            case (state)

                IDLE: begin
                    done        <= 1'b0;
                    clr_accum_r <= 1'b0;
                    if (start) begin
                        clr_accum_r <= 1'b1;
                        tick        <= 4'd0;
                        state       <= CLR;
                    end
                end

                CLR: begin
                    clr_accum_r <= 1'b1;   // gi? reset trong cycle th? hai
                    state       <= CLR2;
                end

                CLR2: begin
                    clr_accum_r <= 1'b0;
                    state       <= RUN;
                end

                RUN: begin
                    if (tick == 4'd6) begin
                        wait_cnt <= 5'd0;
                        state    <= WAIT_PIPE;
                    end else begin
                        tick <= tick + 4'd1;
                    end
                end

                WAIT_PIPE: begin
                    wait_cnt <= wait_cnt + 5'd1;
                    if (wait_cnt == 5'd15) begin   // 16 cycle = d? cho pipeline 7 + margin
                        // Luu k?t qu? C t? các PE
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

                default: state <= IDLE;
            endcase
        end
    end

endmodule