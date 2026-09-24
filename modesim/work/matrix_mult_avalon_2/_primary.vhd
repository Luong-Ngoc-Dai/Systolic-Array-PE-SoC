library verilog;
use verilog.vl_types.all;
entity matrix_mult_avalon_2 is
    port(
        clk             : in     vl_logic;
        reset_n         : in     vl_logic;
        avs_address     : in     vl_logic_vector(5 downto 0);
        avs_write       : in     vl_logic;
        avs_read        : in     vl_logic;
        avs_writedata   : in     vl_logic_vector(31 downto 0);
        avs_readdata    : out    vl_logic_vector(31 downto 0);
        avs_waitrequest : out    vl_logic
    );
end matrix_mult_avalon_2;
