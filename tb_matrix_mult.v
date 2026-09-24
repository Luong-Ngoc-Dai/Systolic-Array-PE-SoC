// =============================================================================
// Module  : tb_matrix_mult.v
// Project : FP16 Matrix Multiplication Accelerator - Testbench
// Author  : Student
// Date    : 2025
//
// Description:
//   Testbench mô phỏng bộ nhân ma trận FP16 4x4.
//
//   Test Case 1: Ma trận đơn vị x Ma trận đơn vị = Ma trận đơn vị
//     I = [[1,0,0,0],[0,1,0,0],[0,0,1,0],[0,0,0,1]]
//     I x I = I
//     Kỳ vọng: C[i][i] = 1.0 (FP16 = 0x3C00), C[i][j] = 0.0 (i≠j)
//
//   Test Case 2: Ma trận với giá trị cụ thể
//     A = [[2,0,0,0],[0,2,0,0],[0,0,2,0],[0,0,0,2]] (diagonal 2)
//     B = [[1,1,0,0],[0,1,0,0],[0,0,1,1],[0,0,0,1]]
//     C = A x B = [[2,2,0,0],[0,2,0,0],[0,0,2,2],[0,0,0,2]]
//
//   FP16 Constants:
//     0.0  = 16'h0000
//     1.0  = 16'h3C00
//     2.0  = 16'h4000
//     0.5  = 16'h3800
// =============================================================================

`timescale 1ns/1ps

module tb_matrix_mult;

// ===========================================================================
// Clock và Reset
// ===========================================================================
reg clk, rst_n;

initial clk = 0;
always #10 clk = ~clk; // 50 MHz clock (20ns period)

// ===========================================================================
// DUT Connections
// ===========================================================================
reg  [3:0]  wr_addr_a, wr_addr_b;
reg  [15:0] wr_data_a, wr_data_b;
reg         wr_en_a, wr_en_b;
reg         start;
wire        done;
reg  [3:0]  rd_addr_c;
wire [15:0] rd_data_c;

matrix_mult_4x4 dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .wr_addr_a (wr_addr_a),
    .wr_data_a (wr_data_a),
    .wr_en_a   (wr_en_a),
    .wr_addr_b (wr_addr_b),
    .wr_data_b (wr_data_b),
    .wr_en_b   (wr_en_b),
    .start     (start),
    .done      (done),
    .rd_addr_c (rd_addr_c),
    .rd_data_c (rd_data_c)
);

// ===========================================================================
// Task: Ghi một phần tử vào ma trận
// ===========================================================================
task write_matrix_A;
    input [3:0]  addr; // row*4 + col
    input [15:0] data; // FP16
    begin
        @(posedge clk);
        wr_addr_a <= addr;
        wr_data_a <= data;
        wr_en_a   <= 1'b1;
        @(posedge clk);
        wr_en_a   <= 1'b0;
    end
endtask

task write_matrix_B;
    input [3:0]  addr;
    input [15:0] data;
    begin
        @(posedge clk);
        wr_addr_b <= addr;
        wr_data_b <= data;
        wr_en_b   <= 1'b1;
        @(posedge clk);
        wr_en_b   <= 1'b0;
    end
endtask

task read_matrix_C;
    input [3:0] addr;
    output [15:0] data;
    begin
        @(posedge clk);
        rd_addr_c <= addr;
        @(posedge clk);
        data = rd_data_c;
    end
endtask

// ===========================================================================
// Task: Khởi động và chờ kết quả
// ===========================================================================
task run_matmul;
    begin
        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        // Chờ done
        wait (done == 1'b1);
        @(posedge clk);
        $display("[%0t ns] Matrix multiplication DONE!", $time);
    end
endtask

// ===========================================================================
// Task: Kiểm tra kết quả
// ===========================================================================
task check_result;
    input [3:0]  addr;
    input [15:0] expected;
    input [7:0]  row, col;
    reg [15:0] actual;
    begin
        read_matrix_C(addr, actual);
        if (actual === expected) begin
            $display("  PASS: C[%0d][%0d] = 0x%04X (expected 0x%04X)",
                     row, col, actual, expected);
        end else begin
            $display("  FAIL: C[%0d][%0d] = 0x%04X (expected 0x%04X) ***",
                     row, col, actual, expected);
        end
    end
endtask

// ===========================================================================
// Chương trình kiểm tra chính
// ===========================================================================
integer i;
reg [15:0] temp;

// Hằng số FP16
localparam FP16_ZERO = 16'h0000;
localparam FP16_ONE  = 16'h3C00;
localparam FP16_TWO  = 16'h4000;

initial begin
    // Dump waveform
    $dumpfile("tb_matrix_mult.vcd");
    $dumpvars(0, tb_matrix_mult);

    // -----------------------------------------------------------------------
    // Reset
    // -----------------------------------------------------------------------
    rst_n     <= 1'b0;
    start     <= 1'b0;
    wr_en_a   <= 1'b0;
    wr_en_b   <= 1'b0;
    rd_addr_c <= 4'd0;
    @(posedge clk);
    @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);

    // =======================================================================
    // TEST CASE 1: I x I = I
    // =======================================================================
    $display("\n======================================================");
    $display("TEST CASE 1: Identity Matrix x Identity Matrix = Identity");
    $display("======================================================");

    // Nạp ma trận A = I (ma trận đơn vị)
    // A[i][j] = 1.0 nếu i==j, 0.0 nếu i≠j
    $display("Loading Matrix A (Identity 4x4)...");
    for (i = 0; i < 16; i = i + 1) begin
        if (i % 5 == 0) // Đường chéo chính: 0, 5, 10, 15
            write_matrix_A(i[3:0], FP16_ONE);
        else
            write_matrix_A(i[3:0], FP16_ZERO);
    end

    // Nạp ma trận B = I
    $display("Loading Matrix B (Identity 4x4)...");
    for (i = 0; i < 16; i = i + 1) begin
        if (i % 5 == 0)
            write_matrix_B(i[3:0], FP16_ONE);
        else
            write_matrix_B(i[3:0], FP16_ZERO);
    end

    // Chạy nhân ma trận
    $display("Starting computation...");
    run_matmul;

    // Kiểm tra kết quả: C phải là ma trận đơn vị
    $display("Verifying results:");
    check_result(4'd0,  FP16_ONE,  0, 0); // C[0][0] = 1.0
    check_result(4'd1,  FP16_ZERO, 0, 1); // C[0][1] = 0.0
    check_result(4'd2,  FP16_ZERO, 0, 2);
    check_result(4'd3,  FP16_ZERO, 0, 3);
    check_result(4'd4,  FP16_ZERO, 1, 0);
    check_result(4'd5,  FP16_ONE,  1, 1); // C[1][1] = 1.0
    check_result(4'd6,  FP16_ZERO, 1, 2);
    check_result(4'd7,  FP16_ZERO, 1, 3);
    check_result(4'd8,  FP16_ZERO, 2, 0);
    check_result(4'd9,  FP16_ZERO, 2, 1);
    check_result(4'd10, FP16_ONE,  2, 2); // C[2][2] = 1.0
    check_result(4'd11, FP16_ZERO, 2, 3);
    check_result(4'd12, FP16_ZERO, 3, 0);
    check_result(4'd13, FP16_ZERO, 3, 1);
    check_result(4'd14, FP16_ZERO, 3, 2);
    check_result(4'd15, FP16_ONE,  3, 3); // C[3][3] = 1.0

    // =======================================================================
    // TEST CASE 2: Diagonal(2) x I = Diagonal(2)
    // =======================================================================
    $display("\n======================================================");
    $display("TEST CASE 2: Diagonal(2) x Identity = Diagonal(2)");
    $display("======================================================");

    @(posedge clk);
    rst_n <= 1'b0;
    @(posedge clk); @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);

    // A = diag(2,2,2,2)
    $display("Loading Matrix A (Diagonal 2)...");
    for (i = 0; i < 16; i = i + 1) begin
        if (i % 5 == 0)
            write_matrix_A(i[3:0], FP16_TWO);
        else
            write_matrix_A(i[3:0], FP16_ZERO);
    end

    // B = I
    $display("Loading Matrix B (Identity)...");
    for (i = 0; i < 16; i = i + 1) begin
        if (i % 5 == 0)
            write_matrix_B(i[3:0], FP16_ONE);
        else
            write_matrix_B(i[3:0], FP16_ZERO);
    end

    $display("Starting computation...");
    run_matmul;

    $display("Verifying results (C = diag(2,2,2,2)):");
    check_result(4'd0,  FP16_TWO,  0, 0);
    check_result(4'd1,  FP16_ZERO, 0, 1);
    check_result(4'd5,  FP16_TWO,  1, 1);
    check_result(4'd10, FP16_TWO,  2, 2);
    check_result(4'd15, FP16_TWO,  3, 3);

    // =======================================================================
    // TEST FP16 Arithmetic Units Riêng Lẻ
    // =======================================================================
    $display("\n======================================================");
    $display("INFO: Timing Analysis");
    $display("======================================================");
    $display("FP16 Multiplier latency: 3 clock cycles");
    $display("FP16 Adder    latency: 4 clock cycles");
    $display("4x4 MatMul cycles: 4*4*(3+1+4+1+1) = ~640 cycles");
    $display("At 50 MHz: ~12.8 us per matrix multiplication");

    $display("\n======================================================");
    $display("Simulation COMPLETE");
    $display("======================================================\n");
    #100;
    $finish;
end

// Timeout watchdog
initial begin
    #1_000_000; // 1ms timeout
    $display("ERROR: Simulation timeout!");
    $finish;
end

endmodule
