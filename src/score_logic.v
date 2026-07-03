// =============================================================================
// score_logic.v - Slow clock divider used to pace the score counter
//
// Divides the 27 MHz system clock down to a ~9 Hz square wave (score_tick).
// pattern_generator watches for rising edges on score_tick and increments
// the on-screen score once per edge while the game is being played.
// =============================================================================

module score_logic (
    input  wire clk,           // 27 MHz system clock
    input  wire gameon,        // Unused here, kept for interface compatibility
    output wire score_tick,    // ~9 Hz toggling output
    output wire obstacle_tick  // Reserved for future use, currently tied low
);

    // 27,000,000 Hz / 9 Hz / 2 (toggle = half period) ≈ 1,500,000 counts
    localparam [20:0] COUNT_MAX = 21'd1499999;

    reg [20:0] counter     = 0;
    reg        score_clock = 0;

    assign score_tick    = score_clock;
    assign obstacle_tick = 0;

    always @(posedge clk) begin
        if (counter == COUNT_MAX) begin
            score_clock <= ~score_clock; // toggle every COUNT_MAX cycles
            counter     <= 0;
        end else begin
            counter <= counter + 1;
        end
    end

endmodule
