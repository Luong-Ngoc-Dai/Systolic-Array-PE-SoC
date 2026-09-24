// =============================================================================
// Module  : top_de2.v
// Project : FP16 Matrix Multiplication Accelerator
// Board   : Altera DE2 (Cyclone II EP2C35F672C6)
// Author  : Student
// Date    : 2025
//
// Description:
//   Module cấp cao nhất cho board DE2.
//   Tích hợp bộ nhân ma trận FP16 với giao diện:
//   - SW[17:0]   : Switch (nhập dữ liệu 16-bit + 2 điều khiển)
//   - KEY[3:0]   : Nút nhấn (tích cực thấp)
//     KEY[0]     : Reset
//     KEY[1]     : Ghi ma trận A
//     KEY[2]     : Ghi ma trận B
//     KEY[3]     : Start tính toán
//   - LEDR[17:0] : LED đỏ (hiển thị trạng thái)
//     LEDR[0]    : Done
//     LEDR[1]    : Busy
//   - LEDG[7:0]  : LED xanh (địa chỉ hiện tại)
//   - HEX0-HEX3  : Hiển thị 16 bit kết quả C[0][0] dưới dạng hex
//
//   Demo: Ma trận đơn vị 4x4 nhân với chính nó => ra ma trận đơn vị
//   Giá trị 1.0 trong FP16 = 0x3C00
//   Giá trị 0.0 trong FP16 = 0x0000
//
//   Quy trình sử dụng:
//   1. Nhấn KEY[0] để reset
//   2. Đặt SW[17:2] = địa chỉ (4-bit), SW[15:0] = giá trị FP16
//   3. Nhấn KEY[1] để ghi vào A, KEY[2] để ghi vào B
//   4. Lặp lại bước 2-3 cho 16 phần tử
//   5. Nhấn KEY[3] để bắt đầu tính
//   6. Đợi LEDR[0] sáng (done)
//   7. Đặt SW[3:0] = địa chỉ C cần đọc
//   8. Đọc kết quả trên HEX displays
// =============================================================================

module top_de2 (
    input         CLOCK_50,      // 50 MHz clock từ DE2
    input  [3:0]  KEY,           // Nút nhấn (tích cực thấp)
    input  [17:0] SW,            // Switch

    output [17:0] LEDR,          // LED đỏ
    output [7:0]  LEDG,          // LED xanh
    output [6:0]  HEX0,          // 7-segment digit 0 (LSB)
    output [6:0]  HEX1,          // 7-segment digit 1
    output [6:0]  HEX2,          // 7-segment digit 2
    output [6:0]  HEX3           // 7-segment digit 3 (MSB)
);

// ===========================================================================
// Tín hiệu nội bộ
// ===========================================================================
wire        clk   = CLOCK_50;
wire        rst_n = KEY[0];     // KEY[0] tích cực thấp = reset

// Debounce và edge detect cho KEY
reg [2:0]   key1_sr, key2_sr, key3_sr;
wire        key1_press = (key1_sr == 3'b110); // Rising edge sau debounce
wire        key2_press = (key2_sr == 3'b110);
wire        key3_press = (key3_sr == 3'b110);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key1_sr <= 3'b111;
        key2_sr <= 3'b111;
        key3_sr <= 3'b111;
    end else begin
        key1_sr <= {key1_sr[1:0], ~KEY[1]}; // Đảo vì KEY tích cực thấp
        key2_sr <= {key2_sr[1:0], ~KEY[2]};
        key3_sr <= {key3_sr[1:0], ~KEY[3]};
    end
end

// ===========================================================================
// Giao diện với matrix_mult_4x4
// ===========================================================================
reg  [3:0]  wr_addr;
reg  [15:0] wr_data;
reg         wr_en_a, wr_en_b;
reg         start;
wire        done;
wire [15:0] rd_data_c;

// Địa chỉ ghi: SW[17:14] (4 bit cao của switch)
// Dữ liệu ghi: SW[15:0]  (16 bit thấp)
// Địa chỉ đọc: SW[3:0]   (dùng khi không ghi)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_addr <= 4'd0;
        wr_data <= 16'd0;
        wr_en_a <= 1'b0;
        wr_en_b <= 1'b0;
        start   <= 1'b0;
    end else begin
        wr_en_a <= 1'b0;
        wr_en_b <= 1'b0;
        start   <= 1'b0;

        if (key1_press) begin
            // Ghi vào ma trận A
            wr_addr <= SW[17:14];
            wr_data <= SW[15:0];
            wr_en_a <= 1'b1;
        end else if (key2_press) begin
            // Ghi vào ma trận B
            wr_addr <= SW[17:14];
            wr_data <= SW[15:0];
            wr_en_b <= 1'b1;
        end else if (key3_press) begin
            start <= 1'b1;
        end
    end
end

// ===========================================================================
// Instantiate Matrix Multiplier
// ===========================================================================
matrix_mult_4x4 u_matmul (
    .clk        (clk),
    .rst_n      (rst_n),
    .wr_addr_a  (wr_addr),
    .wr_data_a  (wr_data),
    .wr_en_a    (wr_en_a),
    .wr_addr_b  (wr_addr),
    .wr_data_b  (wr_data),
    .wr_en_b    (wr_en_b),
    .start      (start),
    .done       (done),
    .rd_addr_c  (SW[3:0]),
    .rd_data_c  (rd_data_c)
);

// ===========================================================================
// LED Output
// ===========================================================================
reg busy;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)      busy <= 1'b0;
    else if (start)  busy <= 1'b1;
    else if (done)   busy <= 1'b0;
end

assign LEDR[0]    = done;
assign LEDR[1]    = busy;
assign LEDR[17:2] = 16'd0;
assign LEDG       = SW[17:14]; // Hiển thị địa chỉ đang nhập

// ===========================================================================
// 7-Segment Decoder
// ===========================================================================
function [6:0] hex_to_7seg;
    input [3:0] hex;
    case (hex)
        4'h0: hex_to_7seg = 7'b100_0000; // 0
        4'h1: hex_to_7seg = 7'b111_1001; // 1
        4'h2: hex_to_7seg = 7'b010_0100; // 2
        4'h3: hex_to_7seg = 7'b011_0000; // 3
        4'h4: hex_to_7seg = 7'b001_1001; // 4
        4'h5: hex_to_7seg = 7'b001_0010; // 5
        4'h6: hex_to_7seg = 7'b000_0010; // 6
        4'h7: hex_to_7seg = 7'b111_1000; // 7
        4'h8: hex_to_7seg = 7'b000_0000; // 8
        4'h9: hex_to_7seg = 7'b001_0000; // 9
        4'hA: hex_to_7seg = 7'b000_1000; // A
        4'hB: hex_to_7seg = 7'b000_0011; // B
        4'hC: hex_to_7seg = 7'b100_0110; // C
        4'hD: hex_to_7seg = 7'b010_0001; // D
        4'hE: hex_to_7seg = 7'b000_0110; // E
        4'hF: hex_to_7seg = 7'b000_1110; // F
        default: hex_to_7seg = 7'b111_1111; // Tắt
    endcase
endfunction

// Hiển thị kết quả C (16-bit FP16) trên HEX3 HEX2 HEX1 HEX0
assign HEX0 = hex_to_7seg(rd_data_c[3:0]);
assign HEX1 = hex_to_7seg(rd_data_c[7:4]);
assign HEX2 = hex_to_7seg(rd_data_c[11:8]);
assign HEX3 = hex_to_7seg(rd_data_c[15:12]);

endmodule
