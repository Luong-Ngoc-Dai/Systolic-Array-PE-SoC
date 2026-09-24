// =============================================================================
// Module  : matrix_mult_avalon_2.v  [FIXED]
// Avalon-MM Slave wrapper kết nối Nios II với systolic core.
// Sửa lỗi:
//   - Đọc C sử dụng combinational rd_data_c (không trễ cycle).
//   - Thêm pipeline cho write data để tăng tần số tối đa.
//   - Gỡ bỏ waitrequest (luôn bằng 0) để CPU không bị stall.
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

    // -------------------------------------------------------------------------
    // Tín hiệu kết nối systolic core
    // -------------------------------------------------------------------------
    reg  [2:0]  wr_addr_a, wr_addr_b;
    reg         wr_en_a,   wr_en_b;
    reg         start;
    wire        done;
    wire [31:0] rd_data_c;

    // Pipeline cho write data (giảm fanout)
    reg [31:0] wrdata_reg;
    always @(posedge clk) wrdata_reg <= avs_writedata;

    // -------------------------------------------------------------------------
    // Write logic (pulsed)
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            wr_en_a   <= 1'b0;
            wr_en_b   <= 1'b0;
            start     <= 1'b0;
            wr_addr_a <= 3'd0;
            wr_addr_b <= 3'd0;
        end else begin
            wr_en_a <= 1'b0;
            wr_en_b <= 1'b0;
            start   <= 1'b0;

            if (avs_write) begin
                // Vùng A: 0x00..0x07
                if (avs_address <= 6'h07) begin
                    wr_addr_a <= avs_address[2:0];
                    wr_en_a   <= 1'b1;
                end
                // Vùng B: 0x08..0x0F
                else if (avs_address >= 6'h08 && avs_address <= 6'h0F) begin
                    wr_addr_b <= avs_address[2:0];
                    wr_en_b   <= 1'b1;
                end
                // CTRL: 0x10 (bit 0 = start)
                else if (avs_address == 6'h10) begin
                    start <= wrdata_reg[0];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read logic (combinational, không waitrequest)
    // -------------------------------------------------------------------------
    always @(*) begin
        avs_readdata = 32'd0;
        if (avs_read) begin
            // STATUS: 0x11
            if (avs_address == 6'h11)
                avs_readdata = {31'd0, done};
            // Vùng C: 0x18..0x1F
            else if (avs_address >= 6'h18 && avs_address <= 6'h1F)
                avs_readdata = rd_data_c;
        end
    end

    assign avs_waitrequest = 1'b0;   // luôn sẵn sàng

    // -------------------------------------------------------------------------
    // Instantiate systolic core
    // -------------------------------------------------------------------------
    matrix_mult_systolic_core u_systolic_core (
        .clk        (clk),
        .rst_n      (reset_n),

        .wr_addr_a  (wr_addr_a),
        .wr_data_a  (wrdata_reg),
        .wr_en_a    (wr_en_a),

        .wr_addr_b  (wr_addr_b),
        .wr_data_b  (wrdata_reg),
        .wr_en_b    (wr_en_b),

        .start      (start),
        .done       (done),

        .rd_addr_c  (avs_address[2:0]),
        .rd_data_c  (rd_data_c)
    );

endmodule