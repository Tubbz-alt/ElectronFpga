library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library UNISIM;
use UNISIM.Vcomponents.all;

entity dcm3 is
    port (CLKIN_IN  : in  std_logic;
          CLKFX_OUT : out std_logic); 
end dcm3;

architecture BEHAVIORAL of dcm3 is
    signal CLK0_BUF    : std_logic;
    signal CLKFX_BUF   : std_logic;
    signal CLKIN_IBUFG : std_logic;
    signal GND_BIT     : std_logic;
begin

    GND_BIT <= '0';
    CLKFX_BUFG_INST : BUFG
        port map (I => CLKFX_BUF, O => CLKFX_OUT);
    
    DCM_INST : DCM
        generic map(CLK_FEEDBACK          => "1X",
                    CLKDV_DIVIDE          => 4.0,  -- 32.00 = 16 * 20 / 10
                    CLKFX_MULTIPLY        => 20,
                    CLKFX_DIVIDE          => 10,
                    CLKIN_DIVIDE_BY_2     => false,
                    CLKIN_PERIOD          => 62.50,
                    CLKOUT_PHASE_SHIFT    => "NONE",
                    DESKEW_ADJUST         => "SYSTEM_SYNCHRONOUS",
                    DFS_FREQUENCY_MODE    => "LOW",
                    DLL_FREQUENCY_MODE    => "LOW",
                    DUTY_CYCLE_CORRECTION => true,
                    FACTORY_JF            => x"C080",
                    PHASE_SHIFT           => 0,
                    STARTUP_WAIT          => false)
        port map (CLKFB    => CLK0_BUF,
                  CLKIN    => CLKIN_IN,
                  DSSEN    => GND_BIT,
                  PSCLK    => GND_BIT,
                  PSEN     => GND_BIT,
                  PSINCDEC => GND_BIT,
                  RST      => GND_BIT,
                  CLKDV    => open,
                  CLKFX    => CLKFX_BUF,
                  CLKFX180 => open,
                  CLK0     => CLK0_BUF,
                  CLK2X    => open,
                  CLK2X180 => open,
                  CLK90    => open,
                  CLK180   => open,
                  CLK270   => open,
                  LOCKED   => open,
                  PSDONE   => open,
                  STATUS   => open);

end BEHAVIORAL;
