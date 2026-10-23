// UART transmitter: 8 data bits, no parity, 1 stop bit (8N1), LSB first.
// CLKS_PER_BIT = clock frequency / baud rate (868 for 100 MHz / 115200).
//
// Pulse `send` for one clock while `busy` is low; `data` is captured at that moment.
// `busy` stays high for the whole frame (10 bit times). A `send` while busy is ignored.
module uart_tx #(
    parameter int CLKS_PER_BIT = 868
) (
    input  logic       clk,
    input  logic       rst,
    input  logic [7:0] data,
    input  logic       send,
    output logic       busy,
    output logic       tx
);
    localparam int CW = $clog2(CLKS_PER_BIT);

    typedef enum logic [1:0] {S_IDLE, S_START, S_DATA, S_STOP} state_t;
    state_t state;
    logic [CW-1:0] cnt;
    logic [2:0]    bit_idx;
    logic [7:0]    shreg;

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= S_IDLE;
            tx      <= 1'b1;
            cnt     <= '0;
            bit_idx <= '0;
            shreg   <= '0;
        end else begin
            case (state)
                S_IDLE: begin
                    tx <= 1'b1;
                    if (send) begin
                        shreg <= data;
                        cnt   <= '0;
                        tx    <= 1'b0;                  // start bit begins
                        state <= S_START;
                    end
                end

                S_START: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt     <= '0;
                        tx      <= shreg[0];            // first data bit (LSB)
                        shreg   <= {1'b0, shreg[7:1]};
                        bit_idx <= '0;
                        state   <= S_DATA;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_DATA: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt <= '0;
                        if (bit_idx == 3'd7) begin
                            tx    <= 1'b1;              // stop bit
                            state <= S_STOP;
                        end else begin
                            tx      <= shreg[0];
                            shreg   <= {1'b0, shreg[7:1]};
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                S_STOP: begin
                    if (cnt == CLKS_PER_BIT - 1) begin
                        cnt   <= '0;
                        state <= S_IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy = (state != S_IDLE);
endmodule
