// =============================================================================
// oled_controller.v - SSD1306 init sequence + raster scan-out engine
//
// On power-up this module sends the standard SSD1306 initialization command
// sequence over I2C (via screen_driver), then continuously loops through all
// 1024 pixels (128 columns x 8 pages) of the display, asking
// pattern_generator for each byte and streaming it out over I2C. Once a full
// frame has been sent, frameNumber increments and the loop repeats.
// =============================================================================

module oled_controller (
    input  wire clk,

    input  wire [7:0] patternByte,   // Pixel-column byte supplied by pattern_generator
    output reg  [9:0] pixelIndex,    // Which pixel (0-1023) we're currently requesting
    output reg  [7:0] frameNumber,   // Increments once per completed frame

    output wire io_scl,
    inout  wire io_sda
);

    // --- I2C driver instance ---
    reg  cmd_start = 0, cmd_write = 0, cmd_stop = 0;
    reg  [7:0] data_out = 0;
    wire tx_done;

    screen_driver my_driver (
        .clk(clk), .io_scl(io_scl), .io_sda(io_sda),
        .cmd_start(cmd_start), .cmd_write(cmd_write), .cmd_stop(cmd_stop),
        .data_in(data_out), .tx_done_tick(tx_done)
    );

    // --- SSD1306 initialization command ROM ---
    // Standard init sequence: display off, clock/multiplex/offset setup,
    // charge pump on, horizontal addressing mode (required so writes auto-
    // advance across the whole 128x64 raster), segment/COM remap, contrast,
    // precharge/VCOM timing, then display on.
    reg [4:0] cmd_index = 0;
    reg [7:0] cmd_data;
    always @* case (cmd_index)
        0: cmd_data = 8'hAE; 1: cmd_data = 8'hD5; 2: cmd_data = 8'h80; 3: cmd_data = 8'hA8;
        4: cmd_data = 8'h3F; 5: cmd_data = 8'hD3; 6: cmd_data = 8'h00; 7: cmd_data = 8'h40;
        8: cmd_data = 8'h8D; 9: cmd_data = 8'h14; 10: cmd_data = 8'h20;
        11: cmd_data = 8'h00; // Horizontal addressing mode - critical for the raster loop below
        12: cmd_data = 8'hA1; 13: cmd_data = 8'hC8; 14: cmd_data = 8'hDA; 15: cmd_data = 8'h12;
        16: cmd_data = 8'h81; 17: cmd_data = 8'hCF; 18: cmd_data = 8'hD9; 19: cmd_data = 8'hF1;
        20: cmd_data = 8'hDB; 21: cmd_data = 8'h40; 22: cmd_data = 8'hA4; 23: cmd_data = 8'hA6;
        24: cmd_data = 8'h2E; 25: cmd_data = 8'hAF; default: cmd_data = 8'hAE;
    endcase
    localparam OLED_addr = 8'h78; // SSD1306 7-bit I2C address (0x3C), shifted left with write bit

    // --- Top-level state machine ---
    reg [3:0] state = 0;
    localparam [3:0]
        IDLE          = 0, START  = 1, ADDR       = 2, CMD        = 3, SEND = 4, STOP = 5, // one-time init
        RASTER_START  = 6, RASTER_ADDR = 7, RASTER_MODE = 8, RASTER_LOOP = 9, RASTER_STOP = 10,
        FRAME_WAIT    = 11;

    reg [20:0] delay_timer = 0;

    always @(posedge clk) begin
        // Default: no command pulses unless a state below sets one.
        cmd_start <= 0; cmd_write <= 0; cmd_stop <= 0;

        case (state)
            // --- One-time SSD1306 init sequence ---
            IDLE:  if (delay_timer < 2000000) delay_timer <= delay_timer + 1; else state <= START; // power-on settle time
            START: begin cmd_start <= 1; if (tx_done) state <= ADDR; end
            ADDR:  begin data_out <= OLED_addr; cmd_write <= 1; if (tx_done) state <= CMD; end
            CMD:   begin data_out <= 8'h00; cmd_write <= 1; if (tx_done) begin state <= SEND; cmd_index <= 0; end end // 0x00 = command stream follows
            SEND:  begin
                data_out <= cmd_data;
                cmd_write <= 1;
                if (tx_done) begin
                    if (cmd_index == 25) state <= STOP;
                    else cmd_index <= cmd_index + 1;
                end
            end
            STOP:  begin cmd_stop <= 1; if (tx_done) state <= RASTER_START; end

            // --- Raster scan: streams the full 1024-byte frame buffer out ---
            RASTER_START: begin cmd_start <= 1; if (tx_done) state <= RASTER_ADDR; end
            RASTER_ADDR:  begin data_out <= OLED_addr; cmd_write <= 1; if (tx_done) state <= RASTER_MODE; end
            RASTER_MODE:  begin
                data_out  <= 8'h40; // 0x40 = data stream follows (as opposed to commands)
                cmd_write <= 1;
                if (tx_done) begin
                    state      <= RASTER_LOOP;
                    pixelIndex <= 0; // begin scan-out at pixel 0
                end
            end

            RASTER_LOOP: begin
                // patternByte is combinationally derived from pixelIndex by
                // pattern_generator, so it's already valid here.
                data_out  <= patternByte;
                cmd_write <= 1;

                if (tx_done) begin
                    if (pixelIndex == 1023) begin
                        state <= RASTER_STOP; // last pixel sent, close out the frame
                    end else begin
                        pixelIndex <= pixelIndex + 1;
                    end
                end
            end

            RASTER_STOP: begin
                cmd_stop <= 1;
                if (tx_done) begin
                    state       <= FRAME_WAIT;
                    frameNumber <= frameNumber + 1; // advance animation/game state
                end
            end

            // --- Pace the frame rate before starting the next scan-out ---
            FRAME_WAIT: begin
                if (delay_timer < 100000) begin
                    delay_timer <= delay_timer + 1;
                end else begin
                    delay_timer <= 0;
                    state       <= RASTER_START; // loop back for the next frame
                end
            end
        endcase
    end

endmodule
