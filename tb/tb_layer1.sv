// Self-checking testbench: layer 1 (784 -> 32) vs. the Python integer golden model.
// Vectors come from python/export_vectors.py (tb/vectors/*.mem).
// For each image it checks all 32 raw accumulators AND the post-ReLU activations.
`timescale 1ns / 1ps

module tb_layer1;
    localparam int N_IN   = 784;
    localparam int N_OUT  = 32;
    localparam int N_IMG  = 10;     // images checked (first N_IMG of the vector files)
    localparam int MAX_IMG = 200;   // vector files may hold up to this many images
    localparam int SHIFT1 = 12;     // must match "shift1" in weights/quant_params.json

    logic clk = 1'b0;
    logic rst, start;
    logic [$clog2(N_IN)-1:0] x_addr;
    logic signed [8:0]       x_data;
    logic                    busy, done;
    logic signed [31:0]      acc_out [N_OUT];
    logic [6:0]              a1      [N_OUT];

    logic [7:0]         images   [MAX_IMG*N_IN];
    logic signed [31:0] exp_acc1 [MAX_IMG*N_OUT];
    logic [7:0]         exp_a1   [MAX_IMG*N_OUT];
    logic [7:0]         img_mem  [N_IN];

    int errors = 0;
    int checks = 0;

    layer #(.N_IN(N_IN), .N_OUT(N_OUT), .W_FILE("w1.mem"), .B_FILE("b1.mem")) dut (
        .clk(clk), .rst(rst), .start(start), .x_addr(x_addr), .x_data(x_data),
        .busy(busy), .done(done), .acc_out(acc_out)
    );

    for (genvar g = 0; g < N_OUT; g++) begin : g_act
        relu_shift #(.SHIFT(SHIFT1)) u_act (.x(acc_out[g]), .y(a1[g]));
    end

    always #5 clk = ~clk;   // 100 MHz

    // Input memory with the same 1-cycle read latency the layer expects.
    always_ff @(posedge clk) x_data <= $signed({1'b0, img_mem[x_addr]});

    // Watchdog
    initial begin
        #50_000_000;
        $display("FAIL: timeout");
        $finish;
    end

    initial begin
        int cycles;

        $readmemh("images.mem",   images);
        $readmemh("exp_acc1.mem", exp_acc1);
        $readmemh("exp_a1.mem",   exp_a1);

        rst = 1; start = 0;
        repeat (3) @(posedge clk);
        @(negedge clk) rst = 0;

        for (int k = 0; k < N_IMG; k++) begin
            for (int p = 0; p < N_IN; p++) img_mem[p] = images[k*N_IN + p];

            @(negedge clk) start = 1;
            @(posedge clk);                 // layer samples start here
            #1 start = 0;
            cycles = 0;
            while (!done) begin
                @(posedge clk);
                #1;
                cycles++;
            end

            checks++;
            if (cycles != N_OUT * (N_IN + 4)) begin
                errors++;
                $display("FAIL: image %0d took %0d cycles, expected %0d",
                         k, cycles, N_OUT * (N_IN + 4));
            end

            for (int n = 0; n < N_OUT; n++) begin
                checks++;
                if (acc_out[n] !== exp_acc1[k*N_OUT + n]) begin
                    errors++;
                    if (errors <= 10)
                        $display("FAIL: image %0d neuron %0d acc=%0d expected=%0d",
                                 k, n, acc_out[n], exp_acc1[k*N_OUT + n]);
                end
                checks++;
                if ({1'b0, a1[n]} !== exp_a1[k*N_OUT + n]) begin
                    errors++;
                    if (errors <= 10)
                        $display("FAIL: image %0d neuron %0d act=%0d expected=%0d",
                                 k, n, a1[n], exp_a1[k*N_OUT + n]);
                end
            end
            @(posedge clk);                 // let the layer return to idle
        end

        if (errors == 0)
            $display("PASS: all %0d checks passed (layer 1 = %0d cycles/image)",
                     checks, N_OUT * (N_IN + 4));
        else
            $display("FAIL: %0d errors in %0d checks", errors, checks);
        $finish;
    end
endmodule
