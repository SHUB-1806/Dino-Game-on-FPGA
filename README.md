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
  top.v               Top-level module, wires everything together
  jump_controller.v   Button -> timed jump pulse
  score_logic.v        27 MHz -> ~9 Hz score tick
  pattern_generator.v  Game state machine + all pixel rendering
  oled_controller.v    SSD1306 init sequence + raster scan-out
  screen_driver.v      Bit-banged I2C master
  dino.cst              Pin/IO constraints
  dino.sdc              Clock timing constraint
```

## Building

1. Install [Gowin EDA](https://www.gowinsemi.com/en/support/home/) (free, requires
   registration).
2. Open `dino_game.gprj`.
3. Run Synthesize -> Place & Route -> generate the bitstream.
4. Program the Tang Nano 20K over USB.

## Can this run without an FPGA?

No, not as-is. This is synthesizable Verilog written specifically for the
Tang Nano 20K's FPGA fabric and its I2C-driven OLED — there's no CPU
instruction stream to execute, so a laptop can't run the bitstream directly.

You have two options if you don't have the board:

- **Simulate it.** Tools like [Icarus Verilog](http://iverilog.icarus.com/) +
  [GTKWave](https://gtkwave.sourceforge.net/), or Verilator, will run the
  RTL and let you inspect signals/waveforms on your laptop. You won't see the
  actual OLED output, but you can verify the game logic (jump timing, score
  counter, collision detection, state machine) is behaving correctly.
- **Get access to an FPGA.** The Tang Nano 20K is inexpensive (~$25-30) and
  is what this project's pin constraints (`dino.cst`) target.

If you want, I can help set up an Icarus Verilog testbench so you can
simulate the game logic locally without any hardware.