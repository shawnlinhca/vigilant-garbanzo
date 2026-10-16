// Sequential argmax: finds the index of the largest of N signed values.
// One comparator, N-1 cycles. Ties go to the lowest index (same as numpy.argmax).
// `idx` holds the result and stays valid until the next `start`.
module argmax #(
    parameter int N = 10
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic                    start,      // pulse for one cycle; vals must stay stable
    input  logic signed [31:0]      vals [N],
    output logic                    busy,
    output logic                    done,       // high for one cycle when idx is final
    output logic [$clog2(N)-1:0]    idx
);
    localparam int KW = $clog2(N);

    typedef enum logic [1:0] {S_IDLE, S_RUN, S_DONE} state_t;
    state_t state;
    logic [KW-1:0] k;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            k     <= '0;
            idx   <= '0;
        end else begin
            case (state)
                S_IDLE: if (start) begin
                    idx   <= '0;          // running best starts as element 0
                    k     <= 1;
                    state <= S_RUN;
                end
                S_RUN: begin
                    if (vals[k] > vals[idx]) idx <= k;   // strict > keeps the first max
                    if (k == N - 1) state <= S_DONE;
                    else            k     <= k + 1'b1;
                end
                S_DONE:  state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    assign busy = (state != S_IDLE);
    assign done = (state == S_DONE);
endmodule
