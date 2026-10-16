// Self-checking testbench for mac.sv.
// A reference model (exp_acc) mirrors the hardware's priority rules using plain
// 64-bit arithmetic; after every clock edge the DUT's acc must match it exactly.
`timescale 1ns / 1ps

module tb_mac;
    logic clk = 1'b0;
    logic rst, load, en;
    logic signed [31:0] load_val;
    logic signed [7:0]  a;
    logic signed [8:0]  b;
    logic signed [31:0] acc;

    longint exp_acc = 0;   // reference model
    int     errors  = 0;
    int     checks  = 0;

    mac dut (.*);

    always #5 clk = ~clk;  // 100 MHz

    // Apply one clock cycle of inputs, update the reference, and compare.
    task automatic step(input logic i_rst, input logic i_load,
                        input logic signed [31:0] i_load_val, input logic i_en,
                        input logic signed [7:0] i_a, input logic signed [8:0] i_b);
        @(negedge clk);
        rst = i_rst; load = i_load; load_val = i_load_val;
        en = i_en; a = i_a; b = i_b;

        if (i_rst)       exp_acc = 0;
        else if (i_load) exp_acc = i_load_val;
        else if (i_en)   exp_acc = exp_acc + i_a * i_b;

        @(posedge clk);
        #1;
        checks++;
        if (acc !== exp_acc[31:0]) begin
            errors++;
            if (errors <= 10)
                $display("FAIL @%0t: acc=%0d expected=%0d", $time, acc, exp_acc);
        end
    endtask

    task automatic accumulate(input logic signed [7:0] i_a, input logic signed [8:0] i_b);
        step(0, 0, 0, 1, i_a, i_b);
    endtask

    initial begin
        int signed bias, n, bmax;
        logic signed [7:0] ra;
        logic signed [8:0] rb;
        logic ren;

        rst = 0; load = 0; en = 0; load_val = 0; a = 0; b = 0;

        // --- Directed tests ---
        step(1, 0, 0, 0, 0, 0);            // reset -> 0
        accumulate(3, 4);                  // 12
        accumulate(-5, 7);                 // -23
        accumulate(-127, 255);             // most negative single product
        accumulate(127, 255);              // most positive single product
        step(0, 0, 0, 0, 100, 100);        // en=0: must hold its value
        step(0, 1, -1000, 1, 50, 50);      // load wins over en -> -1000
        step(1, 1, 5, 1, 1, 1);            // rst wins over load and en -> 0

        // --- Worst-case sums for one layer-1 neuron (784 terms) ---
        step(0, 1, 0, 0, 0, 0);
        repeat (784) accumulate(-127, 255);
        step(0, 1, 0, 0, 0, 0);
        repeat (784) accumulate(127, 255);

        // --- Random neurons: random bias, random weights/inputs, random enable gaps ---
        // Even trials look like layer 1 (784 terms, inputs 0..255);
        // odd trials look like layer 2 (32 terms, inputs 0..127).
        for (int t = 0; t < 200; t++) begin
            bias = int'($urandom_range(2000000)) - 1000000;
            n    = (t % 2 == 0) ? 784 : 32;
            bmax = (t % 2 == 0) ? 255 : 127;
            step(0, 1, bias, 0, 0, 0);
            for (int i = 0; i < n; i++) begin
                ra  = 8'(int'($urandom_range(254)) - 127);
                rb  = 9'($urandom_range(bmax));
                ren = ($urandom_range(9) != 0);   // ~10% idle cycles
                step(0, 0, 0, ren, ra, rb);
            end
        end

        if (errors == 0) $display("PASS: all %0d checks passed", checks);
        else             $display("FAIL: %0d errors in %0d checks", errors, checks);
        $finish;
    end
endmodule
