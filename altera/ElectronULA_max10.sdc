#**************************************************************
# Intel Max 10 SDC settings
# Users are recommended to modify this file to match users logic.
#**************************************************************

# https://fpgawiki.intel.com/wiki/Timing_Constraints is helpful to understand
# the directives in this file.

#**************************************************************
# Create Clock
#**************************************************************

# External clock inputs
create_clock -period "16 MHz" -name clk_in [get_ports clk_in]
create_clock -period "16 MHz" -name clk_osc [get_ports clk_osc]

# Generated clocks (via PLL from 16MHz clk_in or clk_osc)
derive_pll_clocks

# Nicer names for the autogenerated clocks
set clock_16 "max10_pll1_inst|altpll_component|auto_generated|pll1|clk[0]"
set clock_32 "max10_pll1_inst|altpll_component|auto_generated|pll1|clk[1]"
set clock_33 "max10_pll1_inst|altpll_component|auto_generated|pll1|clk[4]"
set clock_40 "max10_pll1_inst|altpll_component|auto_generated|pll1|clk[3]"
set clock_96 "max10_pll1_inst|altpll_component|auto_generated|pll1|clk[2]"
set clock_24 "clock_24"

# We divide clock_96 down with a counter
create_generated_clock \
    -name clock_24 \
    -source [get_clocks $clock_96] \
    -divide_by 4 \
    [get_nets {clock_24}]

# Clock output to SDRAM at 48MHz
create_generated_clock -name ram_output_clock -source $clock_96 -divide_by 2 [get_pins sdram_CLK~reg0|q]

# Clock muxes
create_clock -period "16 MHz" -name clk_16M00_a [get_nets ula|clk_16M00_a]
create_clock -period "16 MHz" -name clk_16M00_b [get_nets ula|clk_16M00_b]
create_clock -period "16 MHz" -name clk_16M00_c [get_nets ula|clk_16M00_c]

# Include this if building with IncludeICEDebugger
# create_clock -period "16 MHz" -name clock_avr {electron_core:bbc_micro|clock_avr}

#**************************************************************
# Set Clock Latency
#**************************************************************

#**************************************************************
# Set Clock Uncertainty
#**************************************************************
derive_clock_uncertainty

#**************************************************************
# Set Input / Output Delay
#**************************************************************
# Board Delay (Data) + Propagation Delay - Board Delay (Clock)

# set_input_delay is easy: after a clock, the previous data value on the pin
# is stable for -min, and the next data value is stable after -max.  So
# -min is the hold time of the remote device, and -max is the clock-to-output
# time.  (Plus board delays.)

# set_output_delay specifies data required time at the specified port relative
# to the clock.  I always have a hard time understanding exactly what's going
# on.

# http://billauer.co.il/blog/2017/04/io-timing-constraints-meaning/ says that
# set_output_delay specifies the range where the clock can change after the
# data changes.  This makes more sense: -min 4 -max -3 means the data has to
# be stable between clock-4ns and clock-(-3ns), which will work for a chip with
# 4ns setup and 3ns hold time.

# With a 10.42ns clock, this constrains so 3ns < clock-to-output < 6.42ns,
# and the data will be stable for at least 7ns.

# Everything seems to assume that remote devices are clocked with the FPGA
# clock, which isn't true in our case: We also generate flash_SCK and
# sdram_CLK, and have to constrain them as well.

# We're running the flash clock at half the system clock, so we're quite
# tolerant of delays.  If we can constrain the forwarded clock and all the
# data signals to at least be close enough to each other, we'll be OK.
# I wonder if we can just constrain the forwarded clock to transition in a
# particular window -- for example -min 3 -max -5, for 8ns stable time and
# a clock-to-output window of 3ns-5.52ns.


# *** QPI flash at 96MHz ***
# W25Q128JV timing parameters:

# Output from FPGA: Flash samples inputs on rising flash_SCK, and needs 3ns
# setup 3ns hold for flash_nCE, 1ns setup 2ns hold for flash_IO*.

# New data is available 6ns (tCLQV) after falling flash_SCK, and old data is
# stable for 1.5ns (tCLQX) after falling flash_SCK.  i.e. for a 96MHz
# (10.42ns) clock, the FPGA has 4.42ns + 1.5ns = 5.92ns to sample data.

# For now we just run the flash at 48 MHz; eventually we'll generate flash_SCK
# using a DDR output and run at 96 MHz, but for now things are a lot easier.

# For now we just want to make sure there's a relatively consistent
# clock-to-output delay across flash_*.  If we say the remote chip needs 3ns
# setup and 5ns hold, we can have a 5.42 ns clock to output time, which
# Quartus should be able to manage.

# flash_SCK (10.42ns) is toggled from $clock_96
set_output_delay -clock $clock_96 -min 3 [get_ports flash_SCK]
set_output_delay -clock $clock_96 -max -5 [get_ports flash_SCK]

# flash_nCE and flash_IO* are updated in sync with the falling edge of flash_SCK
set_output_delay -clock $clock_96 -min 3 [get_ports flash_nCE]
set_output_delay -clock $clock_96 -max -5 [get_ports flash_nCE]
set_output_delay -clock $clock_96 -min 3 [get_ports flash_IO*]
set_output_delay -clock $clock_96 -max -5 [get_ports flash_IO*]

# flash_SCK will go low max 5.42ns after clock_96, and the flash will update
# IO* max 6ns after that, so the clock-to-output time for us relative to the
# next clock cycle is 5.42+6-10.42=1ns + board delays.  The flash will hold
# IO* for 1.25ns after its next clock.

#--- t=0: clock_96 edge, set SCK low ---
# t=3-5.42ns: flash_SCK low
#--- t=10.42ns: clock_96 edge, set SCK high ---
# t=9-11.42ns: flash_IO* driven by flash
# t=13.42-15.84ns: flash_SCK high
#--- t=20.83ns: clock_96 edge, set SCK low ---
# t=23.83-26.25ns: flash_SCK low
# t=25.08-27.5ns: flash_IO* hold time expires
#--- t=31.25ns: clock_96 edge, set SCK high ---

# So the FPGA can latch input data any time between 11.42-25.08ns, i.e.
# from its perspective the flash has a hold time of 4.25ns and a clock
# to output time of 1.02ns.  This would normally not make sense, but we're
# splitting the transaction over two clock cycles.  We're just going to
# be super conservative here and say no hold and 8ns clock-to-output,
# so if the signal is super delayed we still pick it up.

set_input_delay -clock $clock_96 -min 0 [get_ports flash_IO*]
set_input_delay -clock $clock_96 -max 8 [get_ports flash_IO*]


# *** SDRAM at 96MHz ***

# MT48LC16M16A2F4-6A:GTR: 167 MHz CL3, or 100 MHz CL2.

# Access time at CL=3, f=166MHz (tCK(3) =  6ns): tAC(3) = 5.4 ns
# Access time at CL=2, f=100MHz (tCK(2) = 10ns): tAC(2) = 7.5 ns

# Right now we're just running at 48MHz, to make the timing easy.

# sdram_CLK is clock_96 delayed a bit; set the acceptable delay window (0-3ns) here
set sdram_clk_min_delay 0
set sdram_clk_max_delay 3
set clock_96_ns 10.416
#set_output_delay -clock $clock_96 -max [expr $clock_96_ns - $sdram_clk_max_delay] [get_ports sdram_CLK]
set_output_delay -clock $clock_96 -max 2 [get_ports sdram_CLK]
set_output_delay -clock $clock_96 -min -$sdram_clk_min_delay [get_ports sdram_CLK]

# Using -max 3 -min -5 results in 5.5ns of delay being added by the fitter.
# OH.  set_output_delay -min -n results in the output being *delayed* that much to keep the previous data stable.
# So if we want our outputs to change as soon as possible after the clock, we should set -min 0 -max [expr clk_ns - 1].

# Address, control, data outputs to SDRAM
set sdram_board_delay 1
set sdram_setup_time [expr 1.5 + $sdram_board_delay]
set sdram_hold_time 0.8
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_CKE]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_CKE] -add_delay
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_nCS]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_nCS] -add_delay
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_nRAS]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_nRAS] -add_delay
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_nCAS]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_nCAS] -add_delay
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_nWE]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_nWE] -add_delay
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_BA[*]]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_BA[*]] -add_delay
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_A[*]]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_A[*]] -add_delay
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_DQ[*]]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_DQ[*]] -add_delay
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_UDQM]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_UDQM] -add_delay
set_output_delay -clock ram_output_clock -max $sdram_setup_time [get_ports sdram_LDQM]
set_output_delay -clock ram_output_clock -min -$sdram_hold_time [get_ports sdram_LDQM] -add_delay

# Clock-to-output and hold time for SDRAM data outputs.
#set sdram_access_time 7.5
# let's just pretend it comes through quickly; actually we have a multicycle path
set sdram_access_time 2.5
set sdram_data_hold_time 1.8
set_input_delay -clock ram_output_clock -max [expr $sdram_access_time + $sdram_board_delay] [get_ports sdram_DQ[*]]
set_input_delay -clock ram_output_clock -min $sdram_data_hold_time [get_ports sdram_DQ[*]] -add_delay

# Multicycle path for 48 MHz operation
#set_multicycle_path -from [get_clocks {ram_output_clock}] -to [get_clocks $clock_96] -setup -end 2

# Multicycle path for 96 MHz operation if we switch to using a delayed PLL
# set_multicycle_path -from [get_clocks {ram_output_clock}] -to [get_clocks $clock_96] -setup -end 2


# *** Audio DAC at 16MHz (62.5 ns) ***


#**************************************************************
# Set Clock Groups
#**************************************************************

set_clock_groups -asynchronous -group $clock_16 -group $clock_32
set_clock_groups -asynchronous -group $clock_32 -group $clock_16
set_clock_groups -asynchronous -group $clock_16 -group $clock_24
set_clock_groups -asynchronous -group $clock_24 -group $clock_16
set_clock_groups -asynchronous -group $clock_16 -group $clock_33
set_clock_groups -asynchronous -group $clock_33 -group $clock_16
set_clock_groups -asynchronous -group $clock_16 -group $clock_40
set_clock_groups -asynchronous -group $clock_40 -group $clock_16

#**************************************************************
# Set False Path
#**************************************************************



#**************************************************************
# Set Multicycle Path
#**************************************************************



#**************************************************************
# Set Maximum Delay
#**************************************************************



#**************************************************************
# Set Minimum Delay
#**************************************************************



#**************************************************************
# Set Input Transition
#**************************************************************



#**************************************************************
# Set Load
#**************************************************************

