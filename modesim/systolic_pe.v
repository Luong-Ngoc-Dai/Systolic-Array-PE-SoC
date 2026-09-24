// =============================================================================
// Module  : systolic_pe.v  [FIXED v4]
// Processing Element cho Systolic Array 4×4 FP16.
//
// Sửa lỗi:
//   - Thêm thanh ghi add_valid_d để tránh race condition khi cập nhật accum.
//   - Cập nhật accum trễ 1 cycle so với add_valid, đảm bảo adder nhận đúng giá trị.
// =============================================================================

module systolic_pe (
    input         clk,
    input         rst_n,
    input         clr_accum,
    input  [15:0] a_in,
    input  [15:0] b_in,
    input         valid_in,
    output reg [15:0] a_out,
    output reg [15:0] b_out,
    output reg        valid_out_passthrough,
    output [15:0] c_out,
    output        mac_done
);

    wire [15:0] mult_result;
    wire        mult_valid;
    wire [15:0] add_result;
    wire        add_valid;
    reg  [15:0] accum;
    reg         add_valid_d;  // trễ 1 cycle

    // FP16 multiplier (3-cycle pipeline)
    fp16_mult u_mult (
        .clk      (clk),
        .rst_n    (rst_n),
        .a        (a_in),
        .b        (b_in),
        .valid_in (valid_in),
        .result   (mult_result),
        .valid_out(mult_valid)
    );

    // FP16 adder (4-cycle pipeline)
    fp16_add u_add (
        .clk      (clk),
        .rst_n    (rst_n),
        .a        (mult_result),
        .b        (accum),
        .valid_in (mult_valid),
        .result   (add_result),
        .valid_out(add_valid)
    );

    // Delay add_valid để cập nhật accumulator an toàn
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            add_valid_d <= 1'b0;
        else
            add_valid_d <= add_valid;
    end

    // Accumulator update
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            accum <= 16'h0000;
        else if (clr_accum)
            accum <= 16'h0000;
        else if (add_valid_d)
            accum <= add_result;
    end

    // Systolic passthrough (delay 1 cycle)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out                 <= 16'h0000;
            b_out                 <= 16'h0000;
            valid_out_passthrough <= 1'b0;
        end else begin
            a_out                 <= a_in;
            b_out                 <= b_in;
            valid_out_passthrough <= valid_in;
        end
    end

    assign c_out    = accum;
    assign mac_done = add_valid;

endmodule