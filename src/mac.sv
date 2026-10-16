// Multiply-accumulate (MAC) unit: acc <= acc + a * b on every enabled clock cycle.
//
// Sized for the digit classifier:
//   a : signed 8-bit weight (int8)
//   b : signed 9-bit input. A uint8 pixel (0..255) is passed as {1'b0, pixel};
//       a layer-2 activation (0..127) fits the same way.
//   acc: signed 32-bit accumulator (worst case needs ~26 bits, so 32 has headroom)
//
// Priority, highest first: rst, load, en. `load` preloads the accumulator
// (the layer controller uses it to start each neuron at its bias).
module mac #(
    parameter int A_W   = 8,
    parameter int B_W   = 9,
    parameter int ACC_W = 32
) (
    input  logic                    clk,
    input  logic                    rst,       // synchronous reset: acc <= 0
    input  logic                    load,      // acc <= load_val
    input  logic signed [ACC_W-1:0] load_val,
    input  logic                    en,        // acc <= acc + a * b
    input  logic signed [A_W-1:0]   a,
    input  logic signed [B_W-1:0]   b,
    output logic signed [ACC_W-1:0] acc
);
    logic signed [A_W+B_W-1:0] prod;
    assign prod = a * b;

    always_ff @(posedge clk) begin
        if (rst)       acc <= '0;
        else if (load) acc <= load_val;
        else if (en)   acc <= acc + prod;
    end
endmodule
