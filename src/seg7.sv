// Seven-segment driver for the rightmost digit of the Basys 3 display.
// All outputs are active low: 0 lights a segment, 0 enables a digit.
// seg[0] = segment a ... seg[6] = segment g (matches the Basys 3 constraints).
//   show = 1: display `digit` (0-9; 10-15 show "E" for error)
//   show = 0: display "-" (no result yet)
module seg7 (
    input  logic [3:0] digit,
    input  logic       show,
    output logic [6:0] seg,
    output logic [3:0] an,
    output logic       dp
);
    logic [6:0] lit;          // 1 = lit; bit 0 = a ... bit 6 = g

    always_comb begin
        if (!show) lit = 7'b1000000;                  // g only: "-"
        else case (digit)
            4'd0:    lit = 7'b0111111;                // a b c d e f
            4'd1:    lit = 7'b0000110;                // b c
            4'd2:    lit = 7'b1011011;                // a b d e g
            4'd3:    lit = 7'b1001111;                // a b c d g
            4'd4:    lit = 7'b1100110;                // b c f g
            4'd5:    lit = 7'b1101101;                // a c d f g
            4'd6:    lit = 7'b1111101;                // a c d e f g
            4'd7:    lit = 7'b0000111;                // a b c
            4'd8:    lit = 7'b1111111;                // all
            4'd9:    lit = 7'b1101111;                // a b c d f g
            default: lit = 7'b1111001;                // "E": a d e f g
        endcase
    end

    assign seg = ~lit;
    assign an  = 4'b1110;     // only the rightmost digit is enabled
    assign dp  = 1'b1;        // decimal point off
endmodule
