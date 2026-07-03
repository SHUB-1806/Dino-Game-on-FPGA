// =============================================================================
// top.v - Top-level module for the Dino Runner game
//
// Wires together the four subsystems that make up the game:
//   1. oled_controller  - drives the SSD1306 OLED over I2C (raster scan engine)
//   2. jump_controller  - physics: turns a button press into a timed jump
//   3. pattern_generator - graphics: decides what each pixel should look like
//   4. score_logic       - a simple clock divider that ticks ~9 times/sec
//
// Target board: Sipeed Tang Nano 20K (Gowin GW2AR-18C FPGA)
// =============================================================================

module top (
    input  clk,    // 27 MHz onboard oscillator (FPGA pin 4)
    input  btn1,   // Push button, active-low (FPGA pin 15)

    // I2C bus to the SSD1306 OLED display
    output io_scl, // I2C clock
    inout  io_sda  // I2C data (bidirectional, open-drain)
);

    // --- Signals connecting the four subsystems ---
    wire       jumpOffset;    // 1 while the dino is airborne, 0 on the ground
    wire [9:0] pixelIndex;    // Which of the 1024 OLED pixels is being scanned out
    wire [7:0] frameNumbers;  // Frame counter, increments once per full screen redraw
    wire [7:0] patternByte;   // 8 vertical pixels (one column byte) for the current pixelIndex
    wire       gameon;        // 1 while the game is actively being played
    wire       score_tick;    // ~9 Hz pulse used to increment the score

    // 1. Display engine: pulls pixel data from pattern_generator and streams it
    //    out over I2C to the OLED, one byte at a time.
    oled_controller display_engine (
        .clk(clk),
        .io_scl(io_scl),
        .io_sda(io_sda),
        .pixelIndex(pixelIndex),     // requests a pixel from pattern_generator
        .frameNumber(frameNumbers),  // reports current frame number
        .patternByte(patternByte)    // receives the pixel data to send
    );

    // 2. Jump physics: converts a button press into a fixed-duration jump.
    jump_controller jump_inst (
        .clk(clk),
        .btn1(btn1),
        .jumpOffset(jumpOffset),
        .gameon(gameon)
    );

    // 3. Graphics/game logic: renders the dino, ground, obstacle and score,
    //    and owns the start / play / game-over state machine.
    pattern_generator patternGen (
        .pixelIndex(pixelIndex),
        .frameNumber(frameNumbers),
        .patternByte(patternByte),
        .jumpOffset(jumpOffset),
        .button(btn1),
        .gameon(gameon),
        .score_tick(score_tick),
        .clk(clk)
    );

    // 4. Score clock: derives a slow ~9 Hz tick from the 27 MHz system clock.
    score_logic score_counter_only (
        .clk(clk),
        .gameon(gameon),
        .score_tick(score_tick)
    );

endmodule
