// One fully-connected layer built around a single MAC unit.
// Computes acc_out[j] = bias[j] + sum_i weight[j][i] * x[i]  for every neuron j,
// one neuron at a time. ReLU/shift/clamp is applied outside (see relu_shift.sv).
//
// Memories use a registered read (1-cycle latency) so Vivado can map the weights
// to block RAM. The parent supplies x_data with the SAME 1-cycle latency:
// x_data must show the value of x[x_addr] one clock after x_addr is presented.
//
// Weight file layout: neuron-major, address = neuron * N_IN + input (see quantize.py).
// Time per layer: N_OUT * (N_IN + 4) clock cycles.
module layer #(
    parameter int    N_IN   = 784,
    parameter int    N_OUT  = 32,
    parameter string W_FILE = "w1.mem",
    parameter string B_FILE = "b1.mem"
) (
    input  logic                       clk,
    input  logic                       rst,
    input  logic                       start,      // pulse for one cycle when idle
    output logic [$clog2(N_IN)-1:0]    x_addr,     // which input the layer wants
    input  logic signed [8:0]          x_data,     // that input, one cycle later
    output logic                       busy,
    output logic                       done,       // high for one cycle when finished
    output logic signed [31:0]         acc_out [N_OUT]
);
    localparam int IW  = $clog2(N_IN);
    localparam int JW  = (N_OUT > 1) ? $clog2(N_OUT) : 1;
    localparam int WAW = $clog2(N_IN * N_OUT);

    // ---- Weight and bias ROMs (registered read -> block RAM) ----
    logic signed [7:0]  w_rom [0:N_IN*N_OUT-1];
    logic signed [31:0] b_rom [0:N_OUT-1];
    initial begin
        $readmemh(W_FILE, w_rom);
        $readmemh(B_FILE, b_rom);
    end

    logic [WAW-1:0]     w_addr;
    logic [JW-1:0]      j;           // current neuron
    logic [IW-1:0]      i;           // current input index
    logic signed [7:0]  w_data;
    logic signed [31:0] b_data;

    always_ff @(posedge clk) begin
        w_data <= w_rom[w_addr];
        b_data <= b_rom[j];
    end

    // ---- Controller ----
    typedef enum logic [2:0] {
        S_IDLE, S_BIAS_RD, S_BIAS_LD, S_RUN, S_DRAIN, S_STORE, S_DONE
    } state_t;
    state_t state;

    logic en_q;                       // MAC enable, one cycle behind S_RUN (memory latency)
    logic signed [31:0] acc;

    always_ff @(posedge clk) begin
        if (rst) begin
            state  <= S_IDLE;
            i      <= '0;
            j      <= '0;
            w_addr <= '0;
            en_q   <= 1'b0;
        end else begin
            en_q <= (state == S_RUN);
            case (state)
                S_IDLE: if (start) begin
                    j      <= '0;
                    i      <= '0;
                    w_addr <= '0;
                    state  <= S_BIAS_RD;
                end
                S_BIAS_RD: state <= S_BIAS_LD;           // bias read in flight
                S_BIAS_LD: begin                         // MAC loads the bias this cycle
                    i     <= '0;
                    state <= S_RUN;
                end
                S_RUN: begin                             // issue weight/input addresses
                    w_addr <= w_addr + 1'b1;
                    if (i == N_IN - 1) state <= S_DRAIN;
                    else               i     <= i + 1'b1;
                end
                S_DRAIN: state <= S_STORE;               // last product accumulates
                S_STORE: begin
                    acc_out[j] <= acc;
                    if (j == N_OUT - 1) state <= S_DONE;
                    else begin
                        j     <= j + 1'b1;
                        state <= S_BIAS_RD;
                    end
                end
                S_DONE: state <= S_IDLE;
                default: state <= S_IDLE;
            endcase
        end
    end

    assign x_addr = i;
    assign busy   = (state != S_IDLE);
    assign done   = (state == S_DONE);

    mac #(.A_W(8), .B_W(9), .ACC_W(32)) u_mac (
        .clk      (clk),
        .rst      (rst),
        .load     (state == S_BIAS_LD),
        .load_val (b_data),
        .en       (en_q),
        .a        (w_data),
        .b        (x_data),
        .acc      (acc)
    );
endmodule
