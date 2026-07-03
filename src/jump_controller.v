// =============================================================================
// jump_controller.v - Converts a button press into a timed jump pulse
//
// While `gameon` is high, a single press of btn1 (falling edge, since the
// button is active-low) starts a jump that lasts JUMP_DURATION clock cycles.
// `jumpOffset` stays high for the duration of the jump; pattern_generator
// uses it to draw the dino a couple of rows higher on screen.
// =============================================================================

module jump_controller (
    input  wire clk,         // 27 MHz system clock
    input  wire btn1,        // Active-low push button (0 = pressed)
    input  wire gameon,      // Only allow jumping while the game is running
    output reg  jumpOffset   // 1 while the dino is in the air
);

    // Jump length in clock cycles. At 27 MHz, 19,500,000 cycles ≈ 0.72 s.
    parameter JUMP_DURATION = 32'd19_500_000;

    reg [31:0] jumpCounter = 0; // Counts elapsed cycles since jump started
    reg        jumping     = 0; // 1 while a jump is currently in progress

    // Edge detection on the button so a held-down press only triggers one jump.
    reg  prevbtn1 = 1'b1;
    wire btn1pressed = (prevbtn1 == 1'b1) && (btn1 == 1'b0); // falling edge = press

    always @(posedge clk) begin
        prevbtn1 <= btn1;
    end

    always @(posedge clk) begin
        // Start a new jump on a fresh button press, but only if not already
        // jumping and the game is actually in progress.
        if (!jumping && btn1pressed && gameon) begin
            jumping     <= 1;
            jumpCounter <= 0;
            jumpOffset  <= 1;
        end

        // While jumping, hold the jump signal high until the timer expires.
        else if (jumping) begin
            if (jumpCounter < JUMP_DURATION) begin
                jumpCounter <= jumpCounter + 1;
                jumpOffset  <= 1;
            end else begin
                jumping    <= 0; // jump finished, dino lands
                jumpOffset <= 0;
            end
        end

        // Idle: stay on the ground.
        else begin
            jumpOffset <= 0;
        end
    end

endmodule
