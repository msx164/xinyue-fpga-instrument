create_clock -name sys_clk -period 20.000 [get_ports {sys_clk}]

# B5-E-2: asynchronous reset entry of the reset synchronizer only.
# Do not exclude normal data paths or entire clock domains.

set_false_path -to [get_pins {rst_sync_0_s0/CLEAR}]
set_false_path -to [get_pins {rst_sync_1_s0/CLEAR}]