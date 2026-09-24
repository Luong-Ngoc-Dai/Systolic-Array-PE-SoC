`timescale 1ns/1ps

module matrix_mult_systolic_core_tb;

    // -------------------------------------------------------------------------
    // 1. Khai báo các tín hiệu kết nối với UUT (Unit Under Test)
    // -------------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg  [2:0]  wr_addr_a;
    reg  [31:0] wr_data_a;
    reg         wr_en_a;
    reg  [2:0]  wr_addr_b;
    reg  [31:0] wr_data_b;
    reg         wr_en_b;
    reg         start;
    wire        done;
    reg  [2:0]  rd_addr_c;
    wire [31:0] rd_data_c;

    // Định nghĩa hằng số FP16 (Half-Precision)
    localparam [15:0] FP16_ZERO = 16'h0000;
    localparam [15:0] FP16_ONE  = 16'h3C00; // 1.0 trong FP16
    localparam [15:0] FP16_TWO  = 16'h4000; // 2.0 trong FP16

    // -------------------------------------------------------------------------
    // 2. Gọi cấu trúc Lõi cứng Systolic Core cần kiểm thử
    // -------------------------------------------------------------------------
    matrix_mult_systolic_core uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_addr_a  (wr_addr_a),
        .wr_data_a  (wr_data_a),
        .wr_en_a    (wr_en_a),
        .wr_addr_b  (wr_addr_b),
        .wr_data_b  (wr_data_b),
        .wr_en_b    (wr_en_b),
        .start      (start),
        .done       (done),
        .rd_addr_c  (rd_addr_c),
        .rd_data_c  (rd_data_c)
    );

    // -------------------------------------------------------------------------
    // 3. Tạo xung giữ nhịp Clock (Chu kỳ 20ns <=> Tần số 50MHz giống bo DE2)
    // -------------------------------------------------------------------------
    always #10 clk = ~clk;

    // -------------------------------------------------------------------------
    // 4. Kịch bản kích thích kiểm thử (Stimulus Process)
    // -------------------------------------------------------------------------
    integer i;
    initial begin
        // Khởi tạo trạng thái ban đầu
        clk       = 0;
        rst_n     = 0;
        start     = 0;
        wr_en_a   = 0;
        wr_en_b   = 0;
        wr_addr_a = 0;
        wr_addr_b = 0;
        wr_data_a = 0;
        wr_data_b = 0;
        rd_addr_c = 0;

        // Reset hệ thống trong 40ns
        #40;
        rst_n = 1;
        #20;

        $display("[TB] --- BAT DAU TAP KICH THU HUONG MO PHONG ---");
        
        // ---------------------------------------------------------------------
        // BƯỚC 1: CPU nạp Ma trận A vào RAM nội bộ (Packed 32-bit: 2 phan tu/ô)
        // Ma trận A là ma trận đường chéo có giá trị 2.0
        // ---------------------------------------------------------------------
        $display("[TB] 1. Dang nap du lieu vao Bo nho ma tran A...");
        @(posedge clk);
        
        // Word 0: A[0]=2.0, A[1]=0.0  => Packed = 16'h0000_4000
        wr_en_a = 1; wr_addr_a = 3'd0; wr_data_a = {FP16_ZERO, FP16_TWO}; @(posedge clk);
        // Word 1: A[2]=0.0, A[3]=0.0
        wr_en_a = 1; wr_addr_a = 3'd1; wr_data_a = {FP16_ZERO, FP16_ZERO}; @(posedge clk);
        // Word 2: A[4]=0.0, A[5]=2.0  => Packed = 16'h4000_0000
        wr_en_a = 1; wr_addr_a = 3'd2; wr_data_a = {FP16_TWO, FP16_ZERO}; @(posedge clk);
        // Word 3: A[6]=0.0, A[7]=0.0
        wr_en_a = 1; wr_addr_a = 3'd3; wr_data_a = {FP16_ZERO, FP16_ZERO}; @(posedge clk);
        // Word 4: A[8]=0.0, A[9]=0.0
        wr_en_a = 1; wr_addr_a = 3'd4; wr_data_a = {FP16_ZERO, FP16_ZERO}; @(posedge clk);
        // Word 5: A[10]=2.0, A[11]=0.0 => Packed = 16'h0000_4000
        wr_en_a = 1; wr_addr_a = 3'd5; wr_data_a = {FP16_ZERO, FP16_TWO}; @(posedge clk);
        // Word 6: A[12]=0.0, A[13]=0.0
        wr_en_a = 1; wr_addr_a = 3'd6; wr_data_a = {FP16_ZERO, FP16_ZERO}; @(posedge clk);
        // Word 7: A[14]=0.0, A[15]=2.0 => Packed = 16'h4000_0000
        wr_en_a = 1; wr_addr_a = 3'd7; wr_data_a = {FP16_TWO, FP16_ZERO}; @(posedge clk);
        wr_en_a = 0;

        // ---------------------------------------------------------------------
        // BƯỚC 2: CPU nạp Ma trận B vào RAM nội bộ (Packed 32-bit: 2 phan tu/ô)
        // Ma trận B là ma trận đơn vị I (Đường chéo bằng 1.0)
        // ---------------------------------------------------------------------
        $display("[TB] 2. Dang nap du lieu vao Bo nho ma tran B...");
        @(posedge clk);
        
        // Word 0: B[0]=1.0, B[1]=0.0
        wr_en_b = 1; wr_addr_b = 3'd0; wr_data_b = {FP16_ZERO, FP16_ONE}; @(posedge clk);
        // Word 1: B[2]=0.0, B[3]=0.0
        wr_en_b = 1; wr_addr_b = 3'd1; wr_data_b = {FP16_ZERO, FP16_ZERO}; @(posedge clk);
        // Word 2: B[4]=0.0, B[5]=1.0
        wr_en_b = 1; wr_addr_b = 3'd2; wr_data_b = {FP16_ONE, FP16_ZERO}; @(posedge clk);
        // Word 3: B[6]=0.0, B[7]=0.0
        wr_en_b = 1; wr_addr_b = 3'd3; wr_data_b = {FP16_ZERO, FP16_ZERO}; @(posedge clk);
        // Word 4: B[8]=0.0, B[9]=0.0
        wr_en_b = 1; wr_addr_b = 3'd4; wr_data_b = {FP16_ZERO, FP16_ZERO}; @(posedge clk);
        // Word 5: B[10]=1.0, B[11]=0.0
        wr_en_b = 1; wr_addr_b = 3'd5; wr_data_b = {FP16_ZERO, FP16_ONE}; @(posedge clk);
        // Word 6: B[12]=0.0, B[13]=0.0
        wr_en_b = 1; wr_addr_b = 3'd6; wr_data_b = {FP16_ZERO, FP16_ZERO}; @(posedge clk);
        // Word 7: B[14]=0.0, B[15]=1.0
        wr_en_b = 1; wr_addr_b = 3'd7; wr_data_b = {FP16_ONE, FP16_ZERO}; @(posedge clk);
        wr_en_b = 0;

        #40;

        // ---------------------------------------------------------------------
        // BƯỚC 3: Phát xung START kích hoạt FSM chạy mảng Systolic Array
        // ---------------------------------------------------------------------
        $display("[TB] 3. Phat xung START de mang Systolic bat dau tinh toan...");
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // ---------------------------------------------------------------------
        // BƯỚC 4: Chờ cờ DONE từ lõi cứng báo về
        // ---------------------------------------------------------------------
        $display("[TB] 4. Dang cho tin hieu DONE tu FSM...");
        @(posedge done);
        $display("[TB] -> NHAN DUOC TIN HIEU DONE! Thoi gian tinh toan hoan tat.");
        
        #20;

        // ---------------------------------------------------------------------
        // BƯỚC 5: Đọc kiểm tra kết quả Ma trận C và tự động check lỗi
        // Kỳ vọng: C = A x I = A (Đường chéo mang giá trị FP16_TWO = 16'h4000)
        // ---------------------------------------------------------------------
        $display("\n======================================================");
        $display("           KET QUA MO PHONG CO RE PHAN CUNG");
        $display("======================================================");
        
        for (i = 0; i < 8; i = i + 1) begin
            rd_addr_c = i[2:0];
            #5; // Đợi một chút để mạch tổ hợp cập nhật dây ra
            $display("Word C[%0d] (Chua phan tu %0d va %0d) = 0x%h", i, i*2+1, i*2, rd_data_c);
            
            // Tự động kiểm tra độ chính xác của hàng cuối cùng (Điểm mù gây lỗi cũ)
            if (i == 6 && rd_data_c !== {FP16_ZERO, FP16_ZERO}) begin
                $display("[WARNING] Ô C[13]:C[12] sai định thời!");
            end
            if (i == 7 && rd_data_c !== {FP16_TWO, FP16_ZERO}) begin
                $display("[ERROR] Ô C[15]:C[14] bị lệch! Hang cuoi cung bi sai rác.");
            end
        end
        $display("======================================================");

        #100;
        $display("[TB] --- KET THUC MO PHONG ---");
        $stop; // Dừng mô phỏng trong ModelSim
    end

endmodule