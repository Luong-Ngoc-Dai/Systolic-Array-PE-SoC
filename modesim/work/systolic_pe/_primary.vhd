library verilog;
use verilog.vl_types.all;
entity systolic_pe is
    port(
        clk             : in     vl_logic;
        rst_n           : in     vl_logic;
        clr_accum       : in     vl_logic;
        a_in            : in     vl_logic_vector(15 downto 0);
        b_in            : in     vl_logic_vector(15 downto 0);
        valid_in        : in     vl_logic;
        a_out           : out    vl_logic_vector(15 downto 0);
        b_out           : out    vl_logic_vector(15 downto 0);
        valid_out_passthrough: out    vl_logic;
        c_out           : out    vl_logic_vector(15 downto 0);
        mac_done        : out    vl_logic
    );
end systolic_pe;
