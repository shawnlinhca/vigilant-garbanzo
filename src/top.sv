// Warm-up: each LED mirrors the switch directly above it on the Basys 3.
// Purely combinational, no clock needed.
module top (
    input  logic [15:0] sw,
    output logic [15:0] led
);
    assign led = sw;
endmodule
