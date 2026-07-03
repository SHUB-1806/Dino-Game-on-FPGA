# Dino Runner (FPGA + OLED)

A Chrome-Dino-style runner game implemented entirely in Verilog, rendered on a
128x64 SSD1306 I2C OLED display, running on a **Sipeed Tang Nano 20K**
(Gowin GW2AR-18C FPGA).

Press the button to jump over the incoming obstacle. Colliding ends the game;
press the button again to restart.

## Hardware

| Signal    | FPGA Pin | Connects to              |
|-----------|----------|---------------------------|
| `clk`     | 4        | Onboard 27 MHz oscillator |
| `btn1`    | 15       | Push button (active-low)  |
| `io_scl`  | 73       | OLED I2C clock            |
| `io_sda`  | 74       | OLED I2C data              |

## Project structure

```
dino_game.gprj      Gowin IDE project file
src/
  dino.cst              Pin/IO constraints
  dino.sdc              Clock timing constraint
  jump_controller.v   Button -> timed jump pulse
  oled_controller.v    SSD1306 init sequence + raster scan-out
  pattern_generator.v  Game state machine + all pixel rendering
  score_logic.v        27 MHz -> ~9 Hz score tick
  screen_driver.v      Bit-banged I2C master
  top.v               Top-level module, wires everything together
```

## Building

1. Install [Gowin EDA](https://www.gowinsemi.com/en/support/home/) (free, requires
   registration).
2. Open `dino_game.gprj`.
3. Run Synthesize -> Place & Route -> generate the bitstream.
4. Program the Tang Nano 20K over USB.
