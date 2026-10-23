// One fully-connected layer built around P parallel MAC units.
// Computes acc_out[n] = bias[n] + sum_i weight[n][i] * x[i]  for every neuron n.
// Neurons are processed in groups of P (group g = neurons g*P .. g*P+P-1), all P sharing
// the same input stream. ReLU/shift/clamp is applied outside (see relu_shift.sv).
//
// Memories use a registered read (1-cycle latency) so Vivado can map the weights to block
// RAM. One ROM word holds the P weights (or P biases) for a group, so all P MACs are fed
// every cycle. The parent supplies x_data with the SAME 1-cycle latency: x_data must show
// the value of x[x_addr] one clock after x_addr is presented.
//
// Weight file layout (see python/export_parallel.py): word address = group * N_IN + input,
// neuron g*P+p in bits [8p+7:8p]. Bias file: one word per group, neuron g*P+p in bits
// [32p+31:32p]. Neurons past N_OUT in the last group are padding (weight 0, bias 0).
// With P = 1 this is the plain neuron-major layout of weights/w1.mem etc.
//
// Time per layer: ceil(N_OUT / P) * (N_IN + 4) clock cycles.
module layer #(
    parameter int    N_IN   = 784,
    parameter int    N_OUT  = 32,
    parameter int    P      = 1,
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
    localparam int G   = (N_OUT + P - 1) / P;      // number of groups
    localparam int IW  = $clog2(N_IN);
    localparam int GW  = (G > 1) ? $clog2(G) : 1;
    localparam int WAW = $clog2(N_IN * G);

    // ---- Weight and bias ROMs (registered read -> block RAM) ----
    logic [8*P-1:0]  w_rom [0:N_IN*G-1];
    logic [32*P-1:0] b_rom [0:G-1];
    initial begin
        $readmemh(W_FILE, w_rom);
        $readmemh(B_FILE, b_rom);
    end

    logic [WAW-1:0]  w_addr;
    logic [GW-1:0]   j;          // current group
    logic [IW-1:0]   i;          // current input index
    logic [8*P-1:0]  w_data;     // P weights, one per MAC
    logic [32*P-1:0] b_data;     // P biases

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
    logic signed [31:0] acc [P];

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
                S_BIAS_LD: begin                         // MACs load their biases this cycle
                    i     <= '0;
                    state <= S_RUN;
                end
                S_RUN: begin                             // issue weight/input addresses
                    w_addr <= w_addr + 1'b1;
                    if (i == N_IN - 1) state <= S_DRAIN;
                    else               i     <= i + 1'b1;
                end
                S_DRAIN: state <= S_STORE;               // last products accumulate
                S_STORE: begin
                    for (int p = 0; p < P; p++) begin
                        if (int'(j) * P + p < N_OUT) acc_out[int'(j) * P + p] <= acc[p];
                    end
                    if (j == G - 1) state <= S_DONE;
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

    for (genvar p = 0; p < P; p++) begin : g_mac
        mac #(.A_W(8), .B_W(9), .ACC_W(32)) u_mac (
            .clk      (clk),
            .rst      (rst),
            .load     (state == S_BIAS_LD),
            .load_val (b_data[32*p +: 32]),
            .en       (en_q),
            .a        (w_data[8*p +: 8]),
            .b        (x_data),
            .acc      (acc[p])
        );
    end
endmodule
