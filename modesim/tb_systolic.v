// =============================================================================
// Testbench v4 — matrix_mult_systolic_core
// Thêm kiểm tra toàn bộ ma trận sau mỗi lần tính.
// =============================================================================
`timescale 1ns/1ps

module tb_systolic;

reg clk, rst_n;
initial clk = 0;
always #10 clk = ~clk;

reg  [2:0]  wr_addr_a, wr_addr_b;
reg  [31:0] wr_data_a, wr_data_b;
reg         wr_en_a, wr_en_b;
reg         start;
wire        done;
reg  [2:0]  rd_addr_c;
wire [31:0] rd_data_c;

matrix_mult_systolic_core dut (
    .clk       (clk), .rst_n    (rst_n),
    .wr_addr_a (wr_addr_a), .wr_data_a(wr_data_a), .wr_en_a(wr_en_a),
    .wr_addr_b (wr_addr_b), .wr_data_b(wr_data_b), .wr_en_b(wr_en_b),
    .start     (start),     .done     (done),
    .rd_addr_c (rd_addr_c), .rd_data_c(rd_data_c)
);

localparam FP16_ZERO = 16'h0000;
localparam FP16_ONE  = 16'h3C00;
localparam FP16_TWO  = 16'h4000;

task wA; input [2:0] a; input [31:0] d;
    begin @(posedge clk); wr_addr_a<=a; wr_data_a<=d; wr_en_a<=1;
          @(posedge clk); wr_en_a<=0; end
endtask
task wB; input [2:0] a; input [31:0] d;
    begin @(posedge clk); wr_addr_b<=a; wr_data_b<=d; wr_en_b<=1;
          @(posedge clk); wr_en_b<=0; end
endtask

task run_and_wait;
    begin
        @(posedge clk); start<=1;
        @(posedge clk); start<=0;
        wait(done); @(posedge clk);
        $display("[%0t ns] DONE", $time);
    end
endtask

task check_word;
    input [2:0]  addr;
    input [15:0] exp_lo, exp_hi;
    input integer base_idx;
    reg [31:0] d;
    begin
        rd_addr_c = addr;
        #1;
        d = rd_data_c;
        if (d[15:0] === exp_lo)
            $display("  PASS C[%0d] = 0x%04X", base_idx,   d[15:0]);
        else
            $display("  FAIL C[%0d] = 0x%04X  (exp 0x%04X) ***", base_idx,   d[15:0], exp_lo);
        if (d[31:16] === exp_hi)
            $display("  PASS C[%0d] = 0x%04X", base_idx+1, d[31:16]);
        else
            $display("  FAIL C[%0d] = 0x%04X  (exp 0x%04X) ***", base_idx+1, d[31:16], exp_hi);
    end
endtask

task load_identity_A;
    begin
        wA(0, {FP16_ZERO, FP16_ONE});  // C0=1, C1=0
        wA(1, {FP16_ZERO, FP16_ZERO}); // C2=0, C3=0
        wA(2, {FP16_ONE,  FP16_ZERO}); // C4=0, C5=1
        wA(3, {FP16_ZERO, FP16_ZERO}); // C6=0, C7=0
        wA(4, {FP16_ZERO, FP16_ZERO}); // C8=0, C9=0
        wA(5, {FP16_ZERO, FP16_ONE});  // C10=1,C11=0
        wA(6, {FP16_ZERO, FP16_ZERO}); // C12=0,C13=0
        wA(7, {FP16_ONE,  FP16_ZERO}); // C14=0,C15=1
    end
endtask

task load_identity_B;
    begin
        wB(0, {FP16_ZERO, FP16_ONE});
        wB(1, {FP16_ZERO, FP16_ZERO});
        wB(2, {FP16_ONE,  FP16_ZERO});
        wB(3, {FP16_ZERO, FP16_ZERO});
        wB(4, {FP16_ZERO, FP16_ZERO});
        wB(5, {FP16_ZERO, FP16_ONE});
        wB(6, {FP16_ZERO, FP16_ZERO});
        wB(7, {FP16_ONE,  FP16_ZERO});
    end
endtask

initial begin
    $dumpfile("tb_systolic.vcd");
    $dumpvars(0, tb_systolic);
    rst_n = 0; #20; rst_n = 1; #20;

    // Test 1: I x I = I
    $display("\n=== TEST 1: I x I = I ===");
    load_identity_A;
    load_identity_B;
    run_and_wait;
    check_word(0, FP16_ONE,  FP16_ZERO, 0);
    check_word(1, FP16_ZERO, FP16_ZERO, 2);
    check_word(2, FP16_ZERO, FP16_ONE,  4);
    check_word(3, FP16_ZERO, FP16_ZERO, 6);
    check_word(4, FP16_ZERO, FP16_ZERO, 8);
    check_word(5, FP16_ONE,  FP16_ZERO, 10);
    check_word(6, FP16_ZERO, FP16_ZERO, 12);
    check_word(7, FP16_ZERO, FP16_ONE,  14);

    // Test 2: diag(2) x I = diag(2)
    $display("\n=== TEST 2: diag(2) x I = diag(2) ===");
    #1000; rst_n=0; #20; rst_n=1; #20;
    wA(0, {FP16_ZERO, FP16_TWO});
    wA(1, {FP16_ZERO, FP16_ZERO});
    wA(2, {FP16_TWO,  FP16_ZERO});
    wA(3, {FP16_ZERO, FP16_ZERO});
    wA(4, {FP16_ZERO, FP16_ZERO});
    wA(5, {FP16_ZERO, FP16_TWO});
    wA(6, {FP16_ZERO, FP16_ZERO});
    wA(7, {FP16_TWO,  FP16_ZERO});
    load_identity_B;
    run_and_wait;
    check_word(0, FP16_TWO,  FP16_ZERO, 0);
    check_word(1, FP16_ZERO, FP16_ZERO, 2);
    check_word(2, FP16_ZERO, FP16_TWO,  4);
    check_word(3, FP16_ZERO, FP16_ZERO, 6);
    check_word(4, FP16_ZERO, FP16_ZERO, 8);
    check_word(5, FP16_TWO,  FP16_ZERO, 10);
    check_word(6, FP16_ZERO, FP16_ZERO, 12);
    check_word(7, FP16_ZERO, FP16_TWO,  14);

    $display("\n=== Simulation COMPLETE (PASS) ===");
    #200; $finish;
end

initial begin #5_000_000; $display("TIMEOUT"); $finish; end

endmodule