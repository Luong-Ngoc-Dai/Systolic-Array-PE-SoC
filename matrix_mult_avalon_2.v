// =============================================================================
// Module  : matrix_mult_avalon.v
// Project : FP16 Systolic Array Matrix Multiplier 4x4
// Description:
//   Avalon-MM Slave wrapper kết nối Nios II với systolic core.
//   Tối ưu băng thông: mỗi transaction 32-bit mang 2 phần tử FP16.
//
//   Register Map (word address × 4 = byte offset):
//   ┌─────────────┬──────────┬──────────────────────────────────────────┐
//   │ Word Addr   │ Hướng    │ Nội dung                                  │
//   ├─────────────┼──────────┼──────────────────────────────────────────┤
//   │ 0x00..0x07  │ Write    │ Ma trận A: 8 word, mỗi word = [A[2i+1]:A[2i]] │
//   │ 0x08..0x0F  │ Write    │ Ma trận B: 8 word, mỗi word = [B[2i+1]:B[2i]] │
//   │ 0x10        │ Write    │ CTRL: bit[0]=1 để bắt đầu tính toán      │
//   │ 0x11        │ Read     │ STATUS: bit[0]=done                       │
//   │ 0x18..0x1F  │ Read     │ Ma trận C: 8 word, mỗi word = [C[2i+1]:C[2i]] │
//   └─────────────┴──────────┴──────────────────────────────────────────┘
//
//   Cách sử dụng từ code C (Nios II):
//   // Ghi A — pack 2 FP16 vào 1 word 32-bit
//   for (i = 0; i < 8; i++) {
//       alt_u32 packed = ((alt_u32)A[i*2+1] << 16) | A[i*2];
//       IOWR_32DIRECT(BASE, (0x00 + i) * 4, packed);
//   }
//   // Ghi B tương tự với offset 0x08
//   // Ghi CTRL = 1 tại offset 0x10*4
//   // Polling STATUS tại offset 0x11*4
//   // Đọc C với unpack tại offset 0x18..0x1F
// =============================================================================

module matrix_mult_avalon_2 (
    input         clk,
    input         reset_n,

    // Avalon-MM Slave interface
    input  [5:0]  avs_address,
    input         avs_write,
    input         avs_read,
    input  [31:0] avs_writedata,
    output reg [31:0] avs_readdata,
    output        avs_waitrequest
);

    // =========================================================================
    // Tín hiệu nội bộ kết nối với systolic core
    // =========================================================================
    reg  [2:0]  wr_addr_a, wr_addr_b;
    reg         wr_en_a,   wr_en_b;
    reg         start;
    wire        done;
    wire [31:0] rd_data_c;

    // avs_waitrequest = 0: không stall CPU, trả lời ngay trong 1 cycle
    assign avs_waitrequest = 1'b0;

    // =========================================================================
    // Write Logic — giải mã địa chỉ khi CPU ghi
    // =========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_en_a  <= 1'b0;
            wr_en_b  <= 1'b0;
            start    <= 1'b0;
            wr_addr_a <= 3'd0;
            wr_addr_b <= 3'd0;
        end else begin
            // Default: tắt tín hiệu xung (pulse signals)
            wr_en_a <= 1'b0;
            wr_en_b <= 1'b0;
            start   <= 1'b0;

            if (avs_write) begin
                // Vùng A: 0x00..0x07 → word index 0..7
                if (avs_address <= 6'h07) begin
                    wr_addr_a <= avs_address[2:0];
                    wr_en_a   <= 1'b1;
                end
                // Vùng B: 0x08..0x0F → word index 0..7
                else if (avs_address >= 6'h08 && avs_address <= 6'h0F) begin
                    wr_addr_b <= avs_address[2:0];  // [2:0] tự lấy 3 bit thấp
                    wr_en_b   <= 1'b1;
                end
                // CTRL: 0x10 → bit[0] = start
                else if (avs_address == 6'h10) begin
                    start <= avs_writedata[0];
                end
            end
        end
    end

    // =========================================================================
    // Read Logic — trả dữ liệu khi CPU đọc (combinational)
    // =========================================================================
    always @(*) begin
        avs_readdata = 32'd0;
        if (avs_read) begin
            // STATUS: 0x11
            if (avs_address == 6'h11) begin
                avs_readdata = {31'd0, done};
            end
            // Vùng C: 0x18..0x1F
            else if (avs_address >= 6'h18 && avs_address <= 6'h1F) begin
                avs_readdata = rd_data_c;
            end
        end
    end

    // =========================================================================
    // Instantiate Systolic Core
    // =========================================================================
    matrix_mult_systolic_core u_systolic_core (
        .clk        (clk),
        .rst_n      (reset_n),

        // Ma trận A
        .wr_addr_a  (wr_addr_a),
        .wr_data_a  (avs_writedata),    // 32-bit packed trực tiếp từ bus
        .wr_en_a    (wr_en_a),

        // Ma trận B
        .wr_addr_b  (wr_addr_b),
        .wr_data_b  (avs_writedata),    // 32-bit packed trực tiếp từ bus
        .wr_en_b    (wr_en_b),

        // Điều khiển
        .start      (start),
        .done       (done),

        // Kết quả C
        .rd_addr_c  (avs_address[2:0]), // 3 bit thấp của địa chỉ
        .rd_data_c  (rd_data_c)
    );

endmodule