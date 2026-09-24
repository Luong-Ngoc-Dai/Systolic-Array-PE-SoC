// =============================================================================
// Module  : matrix_mult_avalon.v  (FIXED)
// Fixes:
//   1. rd_addr_c now combinational → no 1-cycle read lag on matrix C
//   2. Works correctly with done signal held high until next start
// =============================================================================

module matrix_mult_avalon (
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

// --- Internal signals ---
reg  [3:0]  wr_addr_a, wr_addr_b;
reg  [15:0] wr_data_a, wr_data_b;
reg         wr_en_a, wr_en_b;
reg         start;
wire        done;

// FIX #1: rd_addr_c là combinational, không phải registered
wire [3:0]  rd_addr_c;
wire [15:0] rd_data_c;

assign avs_waitrequest = 1'b0;

// FIX #1: Decode địa chỉ đọc C[] trực tiếp (combinational)
// Avalon đọc không có waitrequest → readdata phải hợp lệ ngay cùng cycle
assign rd_addr_c = avs_address[3:0];

// --- Write logic ---
always @(posedge clk or negedge reset_n) begin
    if (!reset_n) begin
        wr_en_a <= 0; wr_en_b <= 0; start <= 0;
    end else begin
        wr_en_a <= 0; wr_en_b <= 0; start <= 0;
        if (avs_write) begin
            if (avs_address <= 6'h0F) begin                              // A[0..15]
                wr_addr_a <= avs_address[3:0];
                wr_data_a <= avs_writedata[15:0];
                wr_en_a   <= 1;
            end else if (avs_address >= 6'h10 && avs_address <= 6'h1F) begin  // B[0..15]
                wr_addr_b <= avs_address[3:0];
                wr_data_b <= avs_writedata[15:0];
                wr_en_b   <= 1;
            end else if (avs_address == 6'h20) begin                    // ctrl
                start <= avs_writedata[0];
            end
        end
    end
end

// --- Read logic (combinational, đúng chuẩn Avalon-MM) ---
always @(*) begin
    avs_readdata = 32'd0;
    if (avs_read) begin
        if (avs_address == 6'h21)                                    // status: bit[0]=done
            avs_readdata = {31'd0, done};
        else if (avs_address >= 6'h30 && avs_address <= 6'h3F)      // C[0..15]
            avs_readdata = {16'd0, rd_data_c};
    end
end

// --- Instantiate core ---
matrix_mult_4x4 u_core (
    .clk      (clk),
    .rst_n    (reset_n),
    .wr_addr_a(wr_addr_a), .wr_data_a(wr_data_a), .wr_en_a(wr_en_a),
    .wr_addr_b(wr_addr_b), .wr_data_b(wr_data_b), .wr_en_b(wr_en_b),
    .start    (start),
    .done     (done),
    .rd_addr_c(rd_addr_c),
    .rd_data_c(rd_data_c)
);

endmodule
