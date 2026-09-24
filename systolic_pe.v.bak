// =============================================================================
// Module  : systolic_pe.v
// Project : FP16 Systolic Array Matrix Multiplier 4x4
// Description:
//   Processing Element (PE) trong mảng Systolic Array 4x4.
//   Mỗi PE thực hiện: accum = accum + A × B (MAC FP16)
//
//   Luồng dữ liệu chuẩn Systolic:
//   - A chảy từ TRÁI → PHẢI (delay 1 cycle mỗi PE)
//   - B chảy từ TRÊN → DƯỚI (delay 1 cycle mỗi PE)
//   - C tích lũy tại chỗ trong mỗi PE
//
//   Pipeline nội bộ:
//   - fp16_mult: 3 cycle
//   - fp16_add:  4 cycle
//   - Tổng: 7 cycle từ lúc valid_in → add_valid
// =============================================================================

module systolic_pe (
    input         clk,
    input         rst_n,
    input         clr_accum,    // Xóa accumulator về 0 trước phép nhân mới
    input  [15:0] a_in,         // Dữ liệu A từ bên trái vào
    input  [15:0] b_in,         // Dữ liệu B từ bên trên xuống
    input         valid_in,     // Pulse 1 cycle: dữ liệu A,B hợp lệ
    output reg [15:0] a_out,    // Chuyển A sang PE bên phải (delay 1 cycle)
    output reg [15:0] b_out,    // Chuyển B sang PE bên dưới (delay 1 cycle)
    output reg        valid_out_passthrough, // valid_in delay 1 cycle cho PE kế
    output [15:0] c_out,        // Kết quả tích lũy hiện tại
    output        mac_done      // Pulse khi 1 phép MAC hoàn tất (sau 7 cycle)
);

    // -------------------------------------------------------------------------
    // Wires nội bộ
    // -------------------------------------------------------------------------
    wire [15:0] mult_result;
    wire        mult_valid;
    wire [15:0] add_result;
    wire        add_valid;

    reg  [15:0] accum;

    // -------------------------------------------------------------------------
    // Lõi nhân FP16 — Pipeline 3 tầng
    // -------------------------------------------------------------------------
    fp16_mult u_mult (
        .clk      (clk),
        .rst_n    (rst_n),
        .a        (a_in),
        .b        (b_in),
        .valid_in (valid_in),
        .result   (mult_result),
        .valid_out(mult_valid)
    );

    // -------------------------------------------------------------------------
    // Lõi cộng FP16 — Pipeline 4 tầng
    // Cộng kết quả nhân vào accumulator hiện tại
    // -------------------------------------------------------------------------
    fp16_add u_add (
        .clk      (clk),
        .rst_n    (rst_n),
        .a        (mult_result),
        .b        (accum),          // b = giá trị tích lũy hiện tại
        .valid_in (mult_valid),
        .result   (add_result),
        .valid_out(add_valid)
    );

    // -------------------------------------------------------------------------
    // Accumulator — cập nhật sau mỗi phép MAC hoàn tất
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum <= 16'h0000;
        end else if (clr_accum) begin
            accum <= 16'h0000;     // FP16 +0.0
        end else if (add_valid) begin
            accum <= add_result;
        end
    end

    // -------------------------------------------------------------------------
    // Systolic pass-through — A và B delay đúng 1 cycle
    // Đây là đặc tính cốt lõi của Systolic Array:
    // mỗi PE nhận dữ liệu trễ hơn PE trước 1 cycle
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out               <= 16'h0000;
            b_out               <= 16'h0000;
            valid_out_passthrough <= 1'b0;
        end else begin
            a_out               <= a_in;
            b_out               <= b_in;
            valid_out_passthrough <= valid_in;
        end
    end

    // -------------------------------------------------------------------------
    // Output
    // -------------------------------------------------------------------------
    assign c_out    = accum;
    assign mac_done = add_valid;

endmodule