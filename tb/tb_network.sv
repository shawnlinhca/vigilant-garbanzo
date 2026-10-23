// Self-checking testbench for the full network vs. the Python integer golden model.
// Vectors come from python/export_vectors.py (tb/vectors/*.mem); it uses however many
// images are in the files (up to MAX_IMG). Each image is loaded through the DUT's
// write port, exactly as the UART will do on the board.
// PASS = every hardware prediction equals the golden model's prediction.
`timescale 1ns / 1ps

module tb_network;
    localparam int N_IN    = 784;
    localparam int MAX_IMG = 200;
    parameter  int P       = 1;     // parallel MACs (override with: P=4 bash scripts/sim.sh tb_network)
    localparam int P2      = (P > 10) ? 10 : P;
    // layer 1 + layer 2 + 11 cycles of start/argmax overhead (measured: 25587 for P=1)
    localparam int EXP_CYCLES = ((32 + P - 1) / P) * (784 + 4) + ((10 + P2 - 1) / P2) * (32 + 4) + 11;

    logic       clk = 1'b0;
    logic       rst, start;
    logic       img_we;
    logic [9:0] img_waddr;
    logic [7:0] img_wdata;
    logic       busy, done;
    logic [3:0] pred;

    logic [7:0] images   [MAX_IMG*N_IN];
    logic [7:0] labels   [MAX_IMG];
    logic [7:0] exp_pred [MAX_IMG];

    int n_img = 0;
    int errors = 0, hw_correct = 0, golden_correct = 0, cycles = 0;

    network #(.P(P)) dut (
        .clk(clk), .rst(rst),
        .img_we(img_we), .img_waddr(img_waddr), .img_wdata(img_wdata),
        .start(start), .busy(busy), .done(done), .pred(pred)
    );

    always #5 clk = ~clk;   // 100 MHz

    initial begin           // watchdog
        #400_000_000;
        $display("FAIL: timeout");
        $finish;
    end

    initial begin
        $readmemh("images.mem",   images);
        $readmemh("labels.mem",   labels);
        $readmemh("exp_pred.mem", exp_pred);
        while (n_img < MAX_IMG && (^labels[n_img]) !== 1'bx) n_img++;
        if (n_img == 0) begin
            $display("FAIL: no vectors found (run python/export_vectors.py)");
            $finish;
        end

        rst = 1; start = 0; img_we = 0; img_waddr = 0; img_wdata = 0;
        repeat (3) @(posedge clk);
        @(negedge clk) rst = 0;

        for (int k = 0; k < n_img; k++) begin
            // load the image through the write port, one byte per clock
            for (int p = 0; p < N_IN; p++) begin
                @(negedge clk);
                img_we = 1; img_waddr = p; img_wdata = images[k*N_IN + p];
            end
            @(negedge clk) img_we = 0;

            // run the network
            @(negedge clk) start = 1;
            @(posedge clk);
            #1 start = 0;
            cycles = 0;
            while (!done) begin
                @(posedge clk);
                #1;
                cycles++;
            end

            if (cycles != EXP_CYCLES) begin
                errors++;
                if (errors <= 10) $display("FAIL: image %0d took %0d cycles, expected %0d", k, cycles, EXP_CYCLES);
            end
            if ({4'b0, pred} !== exp_pred[k]) begin
                errors++;
                if (errors <= 10)
                    $display("FAIL: image %0d hardware=%0d golden=%0d label=%0d",
                             k, pred, exp_pred[k], labels[k]);
            end
            if ({4'b0, pred} === labels[k])    hw_correct++;
            if (exp_pred[k]  === labels[k])    golden_correct++;
        end

        if (errors == 0)
            $display("PASS: %0d/%0d hardware predictions match the golden model", n_img, n_img);
        else
            $display("FAIL: %0d of %0d predictions differ from the golden model", errors, n_img);
        $display("Hardware correct: %0d/%0d, golden correct: %0d/%0d", hw_correct, n_img, golden_correct, n_img);
        $display("P=%0d  Latency: %0d cycles per image (%0d us at 100 MHz)", P, cycles, cycles / 100);
        $finish;
    end
endmodule
