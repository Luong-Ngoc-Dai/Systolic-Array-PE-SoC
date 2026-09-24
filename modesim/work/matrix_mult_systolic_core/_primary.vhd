library verilog;
use verilog.vl_types.all;
entity matrix_mult_systolic_core is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        wr_addr_a       : in     vl_logic_vector(2 downto 0);
        wr_data_a       : in     vl_logic_vector(31 downto 0);
        wr_en_a         : in     vl_logic;
        wr_addr_b       : in     vl_logic_vector(2 downto 0);
        wr_data_b       : in     vl_logic_vector(31 downto 0);
        wr_en_b         : in     vl_logic;
        start           : in     vl_logic;
        done            : out    vl_logic;
        rd_addr_c       : in     vl_logic_vector(2 downto 0);
        rd_data_c       : out    vl_logic_vector(31 downto 0)
    );
end matrix_mult_systolic_core;
