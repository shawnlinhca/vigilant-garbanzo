// Full digit classifier: 784 -> 32 (ReLU) -> 10 -> argmax.
//
// Usage: write the 784 image bytes through the write port (img_we / img_waddr /
// img_wdata, one byte per clock), pulse `start` for one cycle, wait for `done`.
// `pred` then holds the digit 0..9 until the next run.
//
// SHIFT1 must equal "shift1" in weights/quant_params.json.
module network #(
    parameter int SHIFT1 = 12
) (
    input  logic       clk,
    input  logic       rst,
    // image write port (the UART receiver will drive this in step 7)
    input  logic       img_we,
    input  logic [9:0] img_waddr,
    input  logic [7:0] img_wdata,
    // control
    input  logic       start,
    output logic       busy,
    output logic       done,
    output logic [3:0] pred
);
    localparam int N_IN  = 784;
    localparam int N_HID = 32;
    localparam int N_OUT = 10;

    // ---- Image memory: write port + registered read port (maps to block RAM) ----
    logic [7:0]              img_mem [N_IN];
    logic [$clog2(N_IN)-1:0] x1_addr;
    logic signed [8:0]       x1_data;

    always_ff @(posedge clk) begin
        if (img_we) img_mem[img_waddr] <= img_wdata;
        x1_data <= $signed({1'b0, img_mem[x1_addr]});   // pixel 0..255 as 9-bit signed
    end

    // ---- Layer 1: 784 -> 32 ----
    logic               l1_busy, l1_done;
    logic signed [31:0] acc1 [N_HID];

    layer #(.N_IN(N_IN), .N_OUT(N_HID), .W_FILE("w1.mem"), .B_FILE("b1.mem")) u_l1 (
        .clk(clk), .rst(rst), .start(start),
        .x_addr(x1_addr), .x_data(x1_data),
        .busy(l1_busy), .done(l1_done), .acc_out(acc1)
    );

    // ---- ReLU + shift + clamp on all 32 hidden values ----
    logic [6:0] a1 [N_HID];
    for (genvar g = 0; g < N_HID; g++) begin : g_act
        relu_shift #(.SHIFT(SHIFT1)) u_act (.x(acc1[g]), .y(a1[g]));
    end

    // ---- Layer 2: 32 -> 10, reading the hidden activations (1-cycle read latency) ----
    logic [$clog2(N_HID)-1:0] x2_addr;
    logic signed [8:0]        x2_data;
    always_ff @(posedge clk) x2_data <= $signed({2'b00, a1[x2_addr]});

    logic               l2_busy, l2_done;
    logic signed [31:0] acc2 [N_OUT];

    layer #(.N_IN(N_HID), .N_OUT(N_OUT), .W_FILE("w2.mem"), .B_FILE("b2.mem")) u_l2 (
        .clk(clk), .rst(rst), .start(l1_done),
        .x_addr(x2_addr), .x_data(x2_data),
        .busy(l2_busy), .done(l2_done), .acc_out(acc2)
    );

    // ---- Argmax over the 10 class scores ----
    logic am_busy;
    argmax #(.N(N_OUT)) u_am (
        .clk(clk), .rst(rst), .start(l2_done), .vals(acc2),
        .busy(am_busy), .done(done), .idx(pred)
    );

    assign busy = l1_busy | l2_busy | am_busy;
endmodule
