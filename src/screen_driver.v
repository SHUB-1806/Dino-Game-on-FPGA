// =============================================================================
// screen_driver.v - Bit-banged I2C master
//
// A minimal I2C transmitter used to talk to the SSD1306 OLED. It does not
// implement reads or clock stretching - just enough to START, WRITE a byte,
// and STOP, which is all the OLED init sequence and raster loop need.
//
// Each of the four states (START, TRANSMIT, ACK, STOP) is broken into four
// sub-steps (q_counter 0-3) so that SCL/SDA transitions land on clean,
// evenly-spaced edges of the internal i2c_tick.
// =============================================================================

module screen_driver (
    input  wire clk,          // 27 MHz system clock (FPGA pin 4)

    inout  wire io_sda,       // I2C data line (bidirectional/open-drain)
    output wire io_scl,       // I2C clock line

    input  wire cmd_start,    // Pulse: issue an I2C START condition
    input  wire cmd_write,    // Pulse: transmit data_in as the next byte
    input  wire cmd_stop,     // Pulse: issue an I2C STOP condition
    output reg  tx_done_tick, // Pulses high for one i2c_tick when a command completes

    input  wire [7:0] data_in // Byte to transmit when cmd_write is asserted
);

    // --- Timing parameters ---
    parameter I2C_FREQ = 100000;    // Target I2C bus frequency (100 kHz, standard mode)
    parameter CLK_FREQ  = 27000000; // System clock frequency
    // Each I2C bit takes 4 internal ticks (see q_counter below), so divide
    // the system clock down to 4x the I2C bit rate.
    localparam LIMIT = (CLK_FREQ / (I2C_FREQ * 4));

    // --- I2C tick generator: turns the 27 MHz clock into 4x I2C-rate pulses ---
    reg [30:0] counter  = 0;
    reg        i2c_tick = 0;

    always @(posedge clk) begin
        if (counter == LIMIT) begin
            counter  <= 0;
            i2c_tick <= 1;
        end else begin
            counter  <= counter + 1;
            i2c_tick <= 0;
        end
    end

    // --- I2C bus lines (open-drain) ---
    reg scl_out = 1; // 1 = idle high
    reg sda_out = 1; // 1 = released (high-Z), 0 = actively pulled low

    assign io_scl = scl_out;
    // True open-drain behaviour: only ever drive the line low, otherwise
    // release it to high-Z and let the external pull-up take it high.
    assign io_sda = (sda_out == 0) ? 1'b0 : 1'bz;

    // --- I2C protocol state machine ---
    reg [2:0] state = 0;
    localparam IDLE     = 0;
    localparam START    = 1;
    localparam TRANSMIT = 2;
    localparam ACK      = 3;
    localparam STOP     = 4;

    reg [1:0] q_counter  = 0; // Sub-step within the current state (0-3)
    reg [2:0] bit_cnt    = 0; // Which bit of saved_data is being sent (7 down to 0, MSB first)
    reg [7:0] saved_data = 0; // Latched copy of data_in for the current byte

    always @(posedge clk) begin
        tx_done_tick <= 0; // Default: not done unless a state below says otherwise

        if (i2c_tick) begin
            case (state)

                // Wait for a command; latch it and move to the matching state.
                IDLE: begin
                    if (cmd_start) begin
                        state     <= START;
                        q_counter <= 0;
                    end else if (cmd_write) begin
                        saved_data <= data_in;
                        bit_cnt    <= 7;      // start from the MSB
                        q_counter  <= 0;
                        state      <= TRANSMIT;
                    end else if (cmd_stop) begin
                        state     <= STOP;
                        q_counter <= 0;
                    end
                end

                // I2C START condition: SDA falls while SCL is high.
                START: begin
                    case (q_counter)
                        0: begin scl_out <= 1; sda_out <= 1; end // idle
                        1: begin scl_out <= 1; sda_out <= 0; end // SDA falls -> START
                        2: begin scl_out <= 1; sda_out <= 0; end // hold
                        3: begin scl_out <= 0; sda_out <= 0; tx_done_tick <= 1; state <= IDLE; end
                    endcase
                    q_counter <= (q_counter != 3) ? q_counter + 1 : 0;
                end

                // Shift out one bit per call, MSB first. The slave samples
                // SDA while SCL is high (sub-steps 1-2).
                TRANSMIT: begin
                    case (q_counter)
                        0: begin scl_out <= 0; sda_out <= saved_data[bit_cnt]; end // set up data, clock low
                        1: begin scl_out <= 1; sda_out <= saved_data[bit_cnt]; end // clock rises, slave reads bit
                        2: begin scl_out <= 1; sda_out <= saved_data[bit_cnt]; end // hold clock high
                        3: begin scl_out <= 0; sda_out <= saved_data[bit_cnt]; end // clock falls, ready for next bit
                    endcase
                    if (q_counter != 3) begin
                        q_counter <= q_counter + 1;
                    end else if (bit_cnt == 0) begin
                        state     <= ACK; // all 8 bits sent, wait for ACK slot
                        q_counter <= 0;
                    end else begin
                        bit_cnt   <= bit_cnt - 1;
                        q_counter <= 0;
                    end
                end

                // Release SDA and pulse the clock so the slave can pull SDA
                // low to acknowledge (the ACK bit itself isn't checked here).
                ACK: begin
                    case (q_counter)
                        0: begin scl_out <= 0; sda_out <= 1; end // release SDA for slave to drive
                        1: scl_out <= 1;                          // clock rises
                        2: scl_out <= 1;                          // hold
                        3: begin scl_out <= 0; tx_done_tick <= 1; state <= IDLE; end
                    endcase
                    q_counter <= (q_counter != 3) ? q_counter + 1 : 0;
                end

                // I2C STOP condition: SDA rises while SCL is high.
                STOP: begin
                    case (q_counter)
                        0: begin scl_out <= 0; sda_out <= 0; end // prepare
                        1: begin scl_out <= 1; sda_out <= 0; end // clock rises
                        2: begin scl_out <= 1; sda_out <= 1; end // SDA rises -> STOP
                        3: begin scl_out <= 1; sda_out <= 1; tx_done_tick <= 1; state <= IDLE; end
                    endcase
                    q_counter <= (q_counter != 3) ? q_counter + 1 : 0;
                end

            endcase
        end
    end

endmodule
