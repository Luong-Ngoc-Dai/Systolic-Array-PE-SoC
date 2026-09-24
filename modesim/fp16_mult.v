// =============================================================================
// Module  : fp16_mult.v
// Project : FP16 Matrix Multiplication Accelerator
// Board   : Altera DE2 (Cyclone II EP2C35F672C6)
// Author  : Student
// Date    : 2025
//
// Description:
//   Nhân hai số thực dấu phẩy động nửa độ chính xác (IEEE 754 FP16).
//   Pipeline 3 tầng, độ trễ 3 chu kỳ xung nhịp.
//
// FP16 Format (16 bits):
//   [15]    : Sign (dấu)
//   [14:10] : Exponent (số mũ, bias = 15)
//   [9:0]   : Mantissa (phần định trị, ẩn bit leading 1)
//
// Special values:
//   Zero : exp=0,  mant=0
//   Inf  : exp=31, mant=0
//   NaN  : exp=31, mant≠0
// =============================================================================

module fp16_mult (
    input         clk,
    input         rst_n,      // Reset tích cực thấp
    input  [15:0] a,          // Toán hạng A (FP16)
    input  [15:0] b,          // Toán hạng B (FP16)
    input         valid_in,   // Dữ liệu đầu vào hợp lệ
    output reg [15:0] result, // Kết quả (FP16)
    output reg    valid_out   // Kết quả đầu ra hợp lệ
);

// ---------------------------------------------------------------------------
// Tách các trường của FP16
// ---------------------------------------------------------------------------
wire        a_sign = a[15];
wire [4:0]  a_exp  = a[14:10];
wire [9:0]  a_mant = a[9:0];

wire        b_sign = b[15];
wire [4:0]  b_exp  = b[14:10];
wire [9:0]  b_mant = b[9:0];

// Kiểm tra giá trị đặc biệt
wire a_zero = (a_exp == 5'd0)  && (a_mant == 10'd0);
wire b_zero = (b_exp == 5'd0)  && (b_mant == 10'd0);
wire a_inf  = (a_exp == 5'd31) && (a_mant == 10'd0);
wire b_inf  = (b_exp == 5'd31) && (b_mant == 10'd0);
wire a_nan  = (a_exp == 5'd31) && (a_mant != 10'd0);
wire b_nan  = (b_exp == 5'd31) && (b_mant != 10'd0);

// Thêm implicit leading '1' vào mantissa để có dạng 1.fraction
wire [10:0] a_mant_full = (a_exp == 5'd0) ? {1'b0, a_mant} : {1'b1, a_mant};
wire [10:0] b_mant_full = (b_exp == 5'd0) ? {1'b0, b_mant} : {1'b1, b_mant};

// ---------------------------------------------------------------------------
// STAGE 1: Tính dấu, số mũ, và tích phần định trị
// ---------------------------------------------------------------------------
reg        s1_sign;
reg signed [6:0]  s1_exp;   // 7 bit có dấu để xử lý tràn
reg [21:0] s1_mant_prod;    // 11 x 11 = 22 bit
reg        s1_zero;
reg        s1_inf;
reg        s1_nan;
reg        s1_valid;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s1_valid <= 1'b0;
    end else begin
        s1_sign      <= a_sign ^ b_sign;
        // Cộng số mũ và trừ bias (15)
        s1_exp       <= {2'b00, a_exp} + {2'b00, b_exp} - 7'd15;
        s1_mant_prod <= a_mant_full * b_mant_full;
        s1_zero      <= a_zero | b_zero;
        s1_inf       <= (a_inf | b_inf) & ~(a_nan | b_nan);
        // NaN khi: một trong hai là NaN, hoặc 0 * Inf
        s1_nan       <= a_nan | b_nan | (a_zero & b_inf) | (a_inf & b_zero);
        s1_valid     <= valid_in;
    end
end

// ---------------------------------------------------------------------------
// STAGE 2: Bình thường hóa (Normalize)
// ---------------------------------------------------------------------------
reg        s2_sign;
reg signed [6:0]  s2_exp;
reg [9:0]  s2_mant_norm;
reg        s2_zero;
reg        s2_inf;
reg        s2_nan;
reg        s2_valid;

wire [21:0] s1_mant_prod_w = s1_mant_prod;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s2_valid <= 1'b0;
    end else begin
        s2_sign  <= s1_sign;
        s2_zero  <= s1_zero;
        s2_inf   <= s1_inf;
        s2_nan   <= s1_nan;
        s2_valid <= s1_valid;

        // Tích của hai số dạng 1.xxx là: 1x.xxxxxx hoặc 1.xxxxxx
        // Bit 21 = 1 => dạng 10.xxx => shift right 1, tăng exponent
        // Bit 20 = 1 => dạng 01.xxx => giữ nguyên
        if (s1_mant_prod[21]) begin
            s2_exp       <= s1_exp + 7'd1;
            s2_mant_norm <= s1_mant_prod[20:11]; // Lấy 10 bit sau leading 1
        end else begin
            s2_exp       <= s1_exp;
            s2_mant_norm <= s1_mant_prod[19:10];
        end
    end
end

// ---------------------------------------------------------------------------
// STAGE 3: Đóng gói kết quả (Pack result)
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_out <= 1'b0;
        result    <= 16'd0;
    end else begin
        valid_out <= s2_valid;

        if (s2_nan) begin
            // Not a Number: exp=11111, mant≠0
            result <= 16'h7FFF;
        end else if (s2_inf) begin
            // Vô cực: exp=11111, mant=0
            result <= {s2_sign, 5'b11111, 10'b0};
        end else if (s2_zero) begin
            // Số không
            result <= {s2_sign, 15'b0};
        end else if (s2_exp <= 0) begin
            // Underflow => số quá nhỏ, coi là 0
            result <= {s2_sign, 15'b0};
        end else if (s2_exp >= 31) begin
            // Overflow => vô cực
            result <= {s2_sign, 5'b11111, 10'b0};
        end else begin
            // Số bình thường
            result <= {s2_sign, s2_exp[4:0], s2_mant_norm};
        end
    end
end

endmodule
