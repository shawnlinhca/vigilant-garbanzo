// Self-checking testbench for seg7.sv.
// Expected patterns are written as the letters of the lit segments, so they are checked
// independently of the bit-pattern table inside the design.
`timescale 1ns / 1ps

module tb_seg7;
    logic [3:0] digit;
    logic       show;
    logic [6:0] seg;
    logic [3:0] an;
    logic       dp;
    int errors = 0;

    seg7 dut (.digit(digit), .show(show), .seg(seg), .an(an), .dp(dp));

    // "abc" -> segments a, b, c lit -> active-low pattern with those bits 0
    function automatic logic [6:0] expect_seg(input string lit);
        logic [6:0] m = 7'b0;
        for (int i = 0; i < lit.len(); i++) m[lit[i] - "a"] = 1'b1;
        return ~m;
    endfunction

    task automatic check(input string what, input string lit);
        #1;
        if (seg !== expect_seg(lit)) begin
            errors++;
            $display("FAIL: %s: seg=%b expected %b (lit: %s)", what, seg, expect_seg(lit), lit);
        end
        if (an !== 4'b1110) begin
            errors++;
            $display("FAIL: %s: an=%b expected 1110", what, an);
        end
        if (dp !== 1'b1) begin
            errors++;
            $display("FAIL: %s: decimal point is lit", what);
        end
    endtask

    initial begin
        string digit_segs [10];
        digit_segs = '{"abcdef", "bc", "abdeg", "abcdg", "bcfg",
                       "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"};

        show = 1;
        for (int d = 0; d < 10; d++) begin
            digit = 4'(d);
            check($sformatf("digit %0d", d), digit_segs[d]);
        end
        for (int d = 10; d < 16; d++) begin
            digit = 4'(d);
            check($sformatf("digit %0d (error)", d), "adefg");
        end
        show = 0;
        for (int d = 0; d < 16; d++) begin
            digit = 4'(d);
            check("no result", "g");
        end

        if (errors == 0) $display("PASS: all seven-segment tests passed");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
