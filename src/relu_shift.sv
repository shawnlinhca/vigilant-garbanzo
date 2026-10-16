// ReLU, then round, shift right, and clamp to 0..127 (matches golden.py).
// SHIFT must equal "shift1" in weights/quant_params.json.
module relu_shift #(
    parameter int SHIFT = 12
) (
    input  logic signed [31:0] x,
    output logic        [6:0]  y
);
    localparam int SH_M1 = (SHIFT > 0) ? SHIFT - 1 : 0;
    localparam logic signed [31:0] RND = (SHIFT > 0) ? (32'sd1 <<< SH_M1) : 32'sd0;

    logic signed [31:0] r, s;
    always_comb begin
        r = (x < 0) ? 32'sd0 : x;            // ReLU
        s = (r + RND) >>> SHIFT;             // round to nearest, then scale down
        y = (s > 127) ? 7'd127 : s[6:0];     // clamp
    end
endmodule
