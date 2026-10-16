// Self-checking testbench for top.sv: drives switch patterns and checks the LEDs.
`timescale 1ns / 1ps

module tb_top;
    logic [15:0] sw;
    logic [15:0] led;
    int          errors = 0;

    top dut (.sw(sw), .led(led));

    // Apply one pattern, wait, and compare the output to the expected value.
    task automatic check(input logic [15:0] pattern);
        sw = pattern;
        #10;
        if (led !== pattern) begin
            $display("FAIL: sw=%h led=%h (expected %h)", sw, led, pattern);
            errors++;
        end
    endtask

    initial begin
        check(16'h0000);
        check(16'hFFFF);
        check(16'hAAAA);
        check(16'h5555);
        // Walk a single 1 across every bit
        for (int i = 0; i < 16; i++) check(16'h0001 << i);
        // Some random patterns
        for (int i = 0; i < 50; i++) check($urandom());

        if (errors == 0) $display("PASS: all checks passed");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
