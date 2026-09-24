module de2_top (
    input         CLOCK_50,    
    input  [0:0]  KEY          
);
system u0 (
    .clk_clk       (CLOCK_50), 
    .reset_reset_n (KEY[0])    
);
endmodule