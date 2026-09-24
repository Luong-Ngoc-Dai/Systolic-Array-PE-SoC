// =============================================================================
// Module  : fp16_add.v
// Project : FP16 Matrix Multiplication Accelerator
// Board   : Altera DE2 (Cyclone II EP2C35F672C6)
// Author  : Student
// Date    : 2025
//
// Description:
//   Cộng hai số thực FP16 (IEEE 754 Half Precision).
//   Pipeline 4 tầng, độ trễ 4 chu kỳ xung nhịp.
//
//   Thuật toán cộng FP16:
//   1. So sánh số mũ, căn chỉnh phần định trị
//   2. Cộng/trừ phần định trị
//   3. Bình thường hóa kết quả
//   4. Làm tròn và đóng gói
// =============================================================================

module fp16_add (
    input         clk,
    input         rst_n,
    input  [15:0] a,
    input  [15:0] b,
    input         valid_in,
    output reg [15:0] result,
    output reg    valid_out
);

// ---------------------------------------------------------------------------
// Tách các trường FP16
// ---------------------------------------------------------------------------
wire        a_sign = a[15];
wire [4:0]  a_exp  = a[14:10];
wire [9:0]  a_mant = a[9:0];

wire        b_sign = b[15];
wire [4:0]  b_exp  = b[14:10];
wire [9:0]  b_mant = b[9:0];

// Giá trị đặc biệt
wire a_zero = (a_exp == 5'd0)  && (a_mant == 10'd0);
wire b_zero = (b_exp == 5'd0)  && (b_mant == 10'd0);
wire a_inf  = (a_exp == 5'd31) && (a_mant == 10'd0);
wire b_inf  = (b_exp == 5'd31) && (b_mant == 10'd0);
wire a_nan  = (a_exp == 5'd31) && (a_mant != 10'd0);
wire b_nan  = (b_exp == 5'd31) && (b_mant != 10'd0);

// Mantissa với leading 1 (dạng 1.fraction)
wire [10:0] a_mant_full = (a_exp == 5'd0) ? {1'b0, a_mant} : {1'b1, a_mant};
wire [10:0] b_mant_full = (b_exp == 5'd0) ? {1'b0, b_mant} : {1'b1, b_mant};

// ---------------------------------------------------------------------------
// STAGE 1: Căn chỉnh số mũ (Exponent Alignment)
// ---------------------------------------------------------------------------
// Số nào có số mũ nhỏ hơn sẽ bị dịch phải để căn chỉnh
reg        s1_sign_a, s1_sign_b;
reg [4:0]  s1_exp_max;
reg [11:0] s1_mant_a, s1_mant_b; // 1 bit guard + 11 bit mantissa
reg        s1_swap;               // 1 nếu |b| > |a|
reg        s1_zero, s1_inf, s1_nan;
reg [15:0] s1_special_result;
reg        s1_is_special;
reg        s1_valid;

wire        a_gt_b     = (a_exp > b_exp) || ((a_exp == b_exp) && (a_mant >= b_mant));
wire [4:0]  exp_diff   = a_gt_b ? (a_exp - b_exp) : (b_exp - a_exp);
wire [4:0]  exp_max_c  = a_gt_b ? a_exp : b_exp;
wire [10:0] mant_big_c = a_gt_b ? a_mant_full : b_mant_full;
wire [10:0] mant_sml_c = a_gt_b ? b_mant_full : a_mant_full;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_valid <= 1'b0;
    end else begin
        s1_valid     <= valid_in;
        s1_sign_a    <= a_gt_b ? a_sign : b_sign;
        s1_sign_b    <= a_gt_b ? b_sign : a_sign;
        s1_exp_max   <= exp_max_c;
        // Số lớn hơn: giữ nguyên, thêm 1 bit guard ở đầu
        s1_mant_a    <= {1'b0, mant_big_c};
        // Số nhỏ hơn: dịch phải theo exp_diff
        s1_mant_b    <= (exp_diff >= 12) ? 12'd0 : {1'b0, mant_sml_c} >> exp_diff;

        // Xử lý đặc biệt
        s1_is_special <= a_nan | b_nan | a_inf | b_inf | a_zero | b_zero;
        if (a_nan | b_nan)
            s1_special_result <= 16'h7FFF;
        else if (a_inf & b_inf & (a_sign ^ b_sign))
            s1_special_result <= 16'h7FFF; // +inf + -inf = NaN
        else if (a_inf | b_inf)
            s1_special_result <= a_inf ? a : b; // Inf + finite = Inf
        else if (a_zero)
            s1_special_result <= b;
        else // b_zero
            s1_special_result <= a;
    end
end

// ---------------------------------------------------------------------------
// STAGE 2: Cộng/Trừ phần định trị
// ---------------------------------------------------------------------------
reg        s2_res_sign;
reg [4:0]  s2_exp;
reg [12:0] s2_mant_sum; // 13 bits để chứa carry
reg        s2_is_special;
reg [15:0] s2_special_result;
reg        s2_valid;

wire        do_sub    = s1_sign_a ^ s1_sign_b; // Dấu khác nhau => trừ
wire [12:0] sum_add   = {1'b0, s1_mant_a} + {1'b0, s1_mant_b};
wire [12:0] sum_sub   = {1'b0, s1_mant_a} - {1'b0, s1_mant_b};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s2_valid <= 1'b0;
    end else begin
        s2_valid          <= s1_valid;
        s2_is_special     <= s1_is_special;
        s2_special_result <= s1_special_result;
        s2_exp            <= s1_exp_max;
        s2_res_sign       <= s1_sign_a;

        if (do_sub) begin
            s2_mant_sum <= sum_sub; // |a| >= |b| luôn do đã hoán đổi
        end else begin
            s2_mant_sum <= sum_add;
        end
    end
end

// ---------------------------------------------------------------------------
// STAGE 3: Bình thường hóa (Normalization)
// ---------------------------------------------------------------------------
reg        s3_sign;
reg [4:0]  s3_exp;
reg [10:0] s3_mant;
reg        s3_is_special;
reg [15:0] s3_special_result;
reg        s3_valid;

// Đếm leading zeros của s2_mant_sum để bình thường hóa
// Dùng priority encoder đơn giản
function [3:0] leading_zeros;
    input [12:0] x;
    casez(x)
        13'b1_????????????: leading_zeros = 4'd0;
        13'b01_???????????: leading_zeros = 4'd1;
        13'b001_??????????: leading_zeros = 4'd2;
        13'b0001_?????????: leading_zeros = 4'd3;
        13'b00001_????????: leading_zeros = 4'd4;
        13'b000001_???????: leading_zeros = 4'd5;
        13'b0000001_??????: leading_zeros = 4'd6;
        13'b00000001_?????: leading_zeros = 4'd7;
        13'b000000001_????: leading_zeros = 4'd8;
        13'b0000000001_???: leading_zeros = 4'd9;
        13'b00000000001_??: leading_zeros = 4'd10;
        13'b000000000001_?: leading_zeros = 4'd11;
        default:            leading_zeros = 4'd12;
    endcase
endfunction

wire [3:0] lz = leading_zeros(s2_mant_sum);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s3_valid <= 1'b0;
    end else begin
        s3_valid          <= s2_valid;
        s3_sign           <= s2_res_sign;
        s3_is_special     <= s2_is_special;
        s3_special_result <= s2_special_result;

        if (s2_mant_sum[12]) begin
            // Carry => shift right 1, tăng exponent
            s3_exp  <= s2_exp + 5'd1;
            s3_mant <= s2_mant_sum[11:2]; // Lấy 10 bit, bỏ leading 1
        end else if (lz == 4'd0) begin
            // Đã bình thường, leading 1 ở bit 12
            s3_exp  <= s2_exp;
            s3_mant <= s2_mant_sum[10:1];
        end else begin
            // Shift left để bình thường hóa
            s3_exp  <= (s2_exp >= lz) ? (s2_exp - lz) : 5'd0;
            s3_mant <= (s2_mant_sum << lz) >> 2; // Lấy 10 bit sau leading 1
        end
    end
end

// ---------------------------------------------------------------------------
// STAGE 4: Đóng gói kết quả
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_out <= 1'b0;
        result    <= 16'd0;
    end else begin
        valid_out <= s3_valid;

        if (s3_is_special) begin
            result <= s3_special_result;
        end else if (s3_exp >= 5'd31) begin
            // Overflow => Inf
            result <= {s3_sign, 5'b11111, 10'b0};
        end else begin
            result <= {s3_sign, s3_exp, s3_mant[9:0]};
        end
    end
end

endmodule
