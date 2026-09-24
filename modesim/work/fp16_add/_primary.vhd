library verilog;
use verilog.vl_types.all;
entity fp16_add is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        a               : in     vl_logic_vector(15 downto 0);
        b               : in     vl_logic_vector(15 downto 0);
        valid_in        : in     vl_logic;
        result          : out    vl_logic_vector(15 downto 0);
        valid_out       : out    vl_logic
    );
end fp16_add;
