// UART receiver: 8 data bits, no parity, 1 stop bit (8N1), LSB first.
// CLKS_PER_BIT = clock frequency / baud rate. For the Basys 3: 100 MHz / 115200 = 868.
//
// The input is synchronized with two flip-flops, the start bit is re-checked at its
// midpoint (rejects glitches), and every bit is sampled at its midpoint.
// `valid` pulses for one clock with the received byte on `data` (only if the stop bit
// was high). `frame_err` pulses for one clock instead if the stop bit was low.
module uart_rx #(
    parameter int CLKS_PER_BIT = 868
) (
    input  logic       clk,
    input  logic       rst,
    input  logic       rx,           // serial input (idles high)
    output logic [7:0] data,
    output logic       valid,
    output logic       frame_err
);
    localparam int HALF = CLKS_PER_BIT / 2;
    localparam int CW   = $clog2(CLKS_PER_BIT);

    // 2-flop synchronizer: rx comes from outside the chip, unrelated to our clock
    logic rx_meta, rx_s;
    always_ff @(posedge clk) begin
        if (rst) {rx_meta, rx_s} <= 2'b11;
        else     {rx_meta, rx_s} <= {rx, rx_meta};
    end

    typedef enum logic [1:0] {S_IDLE, S_START, S_DATA, S_STOP} state_t;
    state_t state;
    logic [CW-1:0] cnt;
    logic [2:0]    bit_idx;
    logic [7:0]    shreg;

    always_ff @(posedge clk) begin
        valid     <= 1'b0;
        frame_err <= 1'b0;
        if (rst) begin
            state   <= S_IDLE;
            cnt     <= '0;
            bit_idx <= '0;
            shreg   <= '0;
            data    <= '0;
        end else begin
            case (state)
                S_IDLE: if (!rx_s) begin               // falling edge: start bit begins
                    cnt   <= '0;
                    state <= S_START;
                end

                S_START: begin
                    if (cnt == HALF - 1) begin         // middle of the start bit
                        if (!rx_s) begin               // still low: real start bit
                            cnt     <= '0;
                            bit_idx <= '0;
                            state   <= S_DATA;
                        end else begin
                            state <= S_IDLE;           // glitch
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    if (cnt == CLKS_PER_BIT - 1) begin // middle of the next data bit
                        cnt   <= '0;
                        shreg <= {rx_s, shreg[7:1]};   // LSB arrives first
                        if (bit_idx == 3'd7) state <= S_STOP;
                        else                 bit_idx <= bit_idx + 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    if (cnt == CLKS_PER_BIT - 1) begin // middle of the stop bit
                        if (rx_s) begin
                            data  <= shreg;
                            valid <= 1'b1;
                        end else begin
                            frame_err <= 1'b1;
                        end
                        state <= S_IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
