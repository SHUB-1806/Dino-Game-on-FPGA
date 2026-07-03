// =============================================================================
// pattern_generator.v - Game logic + graphics rendering
//
// This is the heart of the game:
//   - Owns the start / play / game-over state machine
//   - Tracks and renders the score (up to 4 digits)
//   - Scrolls an obstacle across the screen and checks it against the dino
//     for a collision
//   - For every pixelIndex requested by oled_controller, combinationally
//     produces the matching 8-pixel column byte (patternByte)
//
// Display geometry: SSD1306 128x64, horizontal addressing mode.
// pixelIndex 0-1023 maps to 128 columns x 8 "pages" (rows of 8 pixels each).
// =============================================================================

module pattern_generator (
    input  wire [9:0] pixelIndex,   // Pixel column-byte index from oled_controller (0-1023)
    input  wire [7:0] frameNumber,  // Frame counter, advances once per redraw
    input  wire       jumpOffset,   // 1 = dino airborne, 0 = dino on the ground
    output reg  [7:0] patternByte,  // 8 vertical pixels for the requested pixelIndex
    output wire        gameon,       // 1 while STATE_PLAY is active
    input               button,      // Active-low push button
    input               score_tick,  // ~9 Hz pulse, used to advance the score
    input               clk          // 27 MHz system clock
);

    // --- Convert the flat pixel index into (column, page/row) coordinates ---
    wire [6:0] col = pixelIndex % 128; // 0-127
    wire [2:0] row = pixelIndex / 128; // 0-7 (each row = 8 pixel rows tall)

    // --- Sprite / font ROMs (populated in the initial block below) ---
    reg [7:0] catSprite     [0:31];   // 16x16 dino sprite, 2 bytes wide x 16 rows -> 32 bytes
    reg [7:0] numerics      [0:79];   // Digits 0-9, 8x8 glyphs -> 10 * 8 bytes
    reg [7:0] score_display [0:35];   // "SCORE:" label, 6 chars x 6 bytes
    reg [7:0] startGame     [0:1023]; // Full-frame "press button to start" screen
    reg [7:0] gameOver      [0:1023]; // Full-frame "game over" screen

    integer i;
    initial begin
        // 1. Dino sprite (16x16 pixels, 32 bytes: 2 column-bytes per row x 16 rows)
        catSprite[0]=8'h00; catSprite[1]=8'h00; catSprite[2]=8'h00; catSprite[3]=8'h00;
        catSprite[4]=8'h00; catSprite[5]=8'h00; catSprite[6]=8'h00; catSprite[7]=8'hE0;
        catSprite[8]=8'hF0; catSprite[9]=8'hF8; catSprite[10]=8'hEC; catSprite[11]=8'hEC;
        catSprite[12]=8'hFE; catSprite[13]=8'hF0; catSprite[14]=8'h00; catSprite[15]=8'h00;
        catSprite[16]=8'h00; catSprite[17]=8'h00; catSprite[18]=8'hC0; catSprite[19]=8'hC0;
        catSprite[20]=8'hE0; catSprite[21]=8'hF0; catSprite[22]=8'hF8; catSprite[23]=8'hFF;
        catSprite[24]=8'hFF; catSprite[25]=8'hFF; catSprite[26]=8'h93; catSprite[27]=8'h02;
        catSprite[28]=8'h02; catSprite[29]=8'h00; catSprite[30]=8'h00; catSprite[31]=8'h00;

        // 2. Digit glyphs 0-9, each 8 pixels wide x 8 tall (80 bytes total)
        numerics[0]=8'h3E; numerics[1]=8'h51; numerics[2]=8'h49; numerics[3]=8'h45; numerics[4]=8'h3E; numerics[5]=8'h00; numerics[6]=8'h00; numerics[7]=8'h00;
        numerics[8]=8'h00; numerics[9]=8'h42; numerics[10]=8'h7F; numerics[11]=8'h40; numerics[12]=8'h00; numerics[13]=8'h00; numerics[14]=8'h00; numerics[15]=8'h00;
        numerics[16]=8'h42; numerics[17]=8'h61; numerics[18]=8'h51; numerics[19]=8'h49; numerics[20]=8'h46; numerics[21]=8'h00; numerics[22]=8'h00; numerics[23]=8'h00;
        numerics[24]=8'h21; numerics[25]=8'h41; numerics[26]=8'h45; numerics[27]=8'h4B; numerics[28]=8'h31; numerics[29]=8'h00; numerics[30]=8'h00; numerics[31]=8'h00;
        numerics[32]=8'h18; numerics[33]=8'h14; numerics[34]=8'h12; numerics[35]=8'h7F; numerics[36]=8'h10; numerics[37]=8'h00; numerics[38]=8'h00; numerics[39]=8'h00;
        numerics[40]=8'h27; numerics[41]=8'h45; numerics[42]=8'h45; numerics[43]=8'h45; numerics[44]=8'h39; numerics[45]=8'h00; numerics[46]=8'h00; numerics[47]=8'h00;
        numerics[48]=8'h3C; numerics[49]=8'h4A; numerics[50]=8'h49; numerics[51]=8'h49; numerics[52]=8'h30; numerics[53]=8'h00; numerics[54]=8'h00; numerics[55]=8'h00;
        numerics[56]=8'h01; numerics[57]=8'h71; numerics[58]=8'h09; numerics[59]=8'h05; numerics[60]=8'h03; numerics[61]=8'h00; numerics[62]=8'h00; numerics[63]=8'h00;
        numerics[64]=8'h36; numerics[65]=8'h49; numerics[66]=8'h49; numerics[67]=8'h49; numerics[68]=8'h36; numerics[69]=8'h00; numerics[70]=8'h00; numerics[71]=8'h00;
        numerics[72]=8'h06; numerics[73]=8'h49; numerics[74]=8'h49; numerics[75]=8'h29; numerics[76]=8'h1E; numerics[77]=8'h00; numerics[78]=8'h00; numerics[79]=8'h00;

        // 3. "SCORE:" label, 6 characters x 6 bytes wide
        score_display[0]=8'h46; score_display[1]=8'h49; score_display[2]=8'h49; score_display[3]=8'h49; score_display[4]=8'h31; score_display[5]=8'h00;
        score_display[6]=8'h3E; score_display[7]=8'h41; score_display[8]=8'h41; score_display[9]=8'h41; score_display[10]=8'h22; score_display[11]=8'h00;
        score_display[12]=8'h3E; score_display[13]=8'h41; score_display[14]=8'h41; score_display[15]=8'h41; score_display[16]=8'h3E; score_display[17]=8'h00;
        score_display[18]=8'h7F; score_display[19]=8'h09; score_display[20]=8'h19; score_display[21]=8'h29; score_display[22]=8'h46; score_display[23]=8'h00;
        score_display[24]=8'h7F; score_display[25]=8'h49; score_display[26]=8'h49; score_display[27]=8'h49; score_display[28]=8'h41; score_display[29]=8'h00;
        score_display[30]=8'h00; score_display[31]=8'h36; score_display[32]=8'h36; score_display[33]=8'h00; score_display[34]=8'h00; score_display[35]=8'h00;

        // 4. Full-screen "start" and "game over" frames, generated procedurally
        for (i = 0; i < 1024; i = i + 1) begin
            startGame[i] = 8'h00; // blank/black screen while waiting to start
            gameOver[i]  = 8'hAA; // striped pattern (10101010) to signal game over
        end
    end

    // --- Layout constants ---
    localparam CAT_X              = 40;  // dino's fixed horizontal position
    localparam CAT_WIDTH          = 16;
    localparam OBS_WIDTH          = 8;
    localparam SCREEN_WIDTH       = 128;
    localparam SCORE_ROW          = 0;
    localparam CHAR_WIDTH         = 8;
    localparam SCORE_LABEL_WIDTH  = 34;
    localparam SCORE_COL          = 49;
    localparam SCORE_DIGIT_GAP    = 2;

    // --- Score digit column positions, laid out left-to-right after the label ---
    localparam DIGIT_1_COL = SCORE_COL + SCORE_LABEL_WIDTH + SCORE_DIGIT_GAP;
    localparam DIGIT_2_COL = DIGIT_1_COL + CHAR_WIDTH;
    localparam DIGIT_3_COL = DIGIT_2_COL + CHAR_WIDTH;
    localparam DIGIT_4_COL = DIGIT_3_COL + CHAR_WIDTH;

    // --- Score value and its individual decimal digits ---
    reg [13:0] score = 0;
    wire [3:0] score_thousands = score / 1000;
    wire [3:0] score_hundreds  = (score % 1000) / 100;
    wire [3:0] score_tens      = (score % 100) / 10;
    wire [3:0] score_ones      = score % 10;

    // --- Obstacle motion and collision detection ---
    // Obstacle re-enters from the right edge and scrolls left at 2 px/frame,
    // wrapping around once it passes off the left edge.
    wire [6:0] obsX    = SCREEN_WIDTH - ((frameNumber * 2) % (SCREEN_WIDTH + OBS_WIDTH));
    wire [6:0] obsXEnd = obsX + OBS_WIDTH;

    wire horizontalOverlap = (obsX < (CAT_X + CAT_WIDTH)) && (obsXEnd > CAT_X);
    wire catOnGround       = !jumpOffset; // can only collide while not jumping
    wire collisionDetected = horizontalOverlap && catOnGround;

    // --- Game state machine ---
    localparam [1:0] STATE_START_GAME = 2'b00;
    localparam [1:0] STATE_PLAY       = 2'b01;
    localparam [1:0] STATE_GAME_OVER  = 2'b10;
    reg [1:0] currentState = STATE_START_GAME;

    assign gameon = (currentState == STATE_PLAY);

    // --- Edge-detection registers for button, score tick and frame update ---
    reg        prevButton    = 1;
    reg        prevScoreTick = 0;
    reg [7:0]  prevFrame     = 0;

    // --- Main sequential logic: score updates and state transitions ---
    always @(posedge clk) begin
        prevButton    <= button;
        prevScoreTick <= score_tick;
        prevFrame     <= frameNumber;

        // Increment score once per score_tick rising edge while playing;
        // reset it back to zero while sitting on the start screen.
        if (score_tick && !prevScoreTick) begin
            if (currentState == STATE_PLAY)
                score <= score + 1;
            else if (currentState == STATE_START_GAME)
                score <= 0;
        end

        // Advance the state machine once per frame (not every clock cycle).
        if (frameNumber != prevFrame) begin
            case (currentState)
                STATE_START_GAME: begin
                    // Button falling edge (released -> pressed) begins the game.
                    if (prevButton == 1 && button == 0)
                        currentState <= STATE_PLAY;
                end

                STATE_PLAY: begin
                    if (collisionDetected)
                        currentState <= STATE_GAME_OVER;
                end

                STATE_GAME_OVER: begin
                    // Button press returns to the start screen.
                    if (prevButton == 1 && button == 0)
                        currentState <= STATE_START_GAME;
                end
            endcase
        end
    end

    // --- Column offsets into the label/digit glyphs for the current pixel ---
    wire [4:0] label_col_offset  = col - SCORE_COL;
    wire [2:0] char_col_offset_1 = col - DIGIT_1_COL;
    wire [2:0] char_col_offset_2 = col - DIGIT_2_COL;
    wire [2:0] char_col_offset_3 = col - DIGIT_3_COL;
    wire [2:0] char_col_offset_4 = col - DIGIT_4_COL;

    // --- Combinational rendering: pick the byte for the requested pixel ---
    always @(*) begin
        patternByte = 8'h00; // default: background (black)

        case (currentState)
            STATE_START_GAME: patternByte = startGame[pixelIndex];
            STATE_GAME_OVER:  patternByte = gameOver[pixelIndex];

            STATE_PLAY: begin
                // A. Ground line
                if (row == 6) patternByte = 8'hF0;

                // B. "SCORE: NNNN" label + digits
                else if (row == SCORE_ROW && (col >= SCORE_COL && col < DIGIT_4_COL + CHAR_WIDTH)) begin
                    if (col < DIGIT_1_COL - SCORE_DIGIT_GAP)
                        patternByte = score_display[label_col_offset];
                    else if (col >= DIGIT_1_COL && col < DIGIT_2_COL)
                        patternByte = numerics[(score_thousands * CHAR_WIDTH) + char_col_offset_1];
                    else if (col >= DIGIT_2_COL && col < DIGIT_3_COL)
                        patternByte = numerics[(score_hundreds * CHAR_WIDTH) + char_col_offset_2];
                    else if (col >= DIGIT_3_COL && col < DIGIT_4_COL)
                        patternByte = numerics[(score_tens * CHAR_WIDTH) + char_col_offset_3];
                    else if (col >= DIGIT_4_COL)
                        patternByte = numerics[(score_ones * CHAR_WIDTH) + char_col_offset_4];
                end

                // C. Dino sprite - shifts up two rows while jumping
                else if ((row == (jumpOffset ? 1 : 4) || row == (jumpOffset ? 2 : 5)) &&
                         (col >= CAT_X && col < CAT_X + CAT_WIDTH)) begin
                    patternByte = catSprite[(row - (jumpOffset ? 1 : 4)) * 16 + (col - CAT_X)];
                end

                // D. Scrolling obstacle
                else if (row == 5 && (col >= obsX && col < obsXEnd)) begin
                    patternByte = 8'hFF;
                end
            end
        endcase
    end

endmodule
