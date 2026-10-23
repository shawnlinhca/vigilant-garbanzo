// System testbench for board_top.sv: a simulated PC sends real MNIST images over the serial
// line and checks the ASCII reply, the seven-segment display, and the LEDs.
// Uses the vectors from python/export_vectors.py (expected digits come from the golden model).
// Bit time is shortened to 16 clocks so this finishes quickly; uart_rx/uart_tx are tested
// separately at the real 868 clocks per bit.
`timescale 1ns / 1ps

module tb_board_top;
    localparam int CPB     = 16;
    localparam int N_IN    = 784;
    localparam int MAX_IMG = 200;

    logic clk = 1'b0;
    logic btnC = 1'b0;
    logic RsRx = 1'b1;
    logic RsTx;
    logic [15:0] led;
    logic [6:0]  seg;
    logic [3:0]  an;
    logic        dp;

    logic [7:0] images   [MAX_IMG*N_IN];
    logic [7:0] exp_pred [MAX_IMG];

    logic [7:0] q_tx [$];        // bytes the board has sent back
    int errors = 0;

    board_top #(.CLKS_PER_BIT(CPB), .TIMEOUT_CLKS(20000)) dut (
        .clk(clk), .btnC(btnC), .RsRx(RsRx), .RsTx(RsTx),
        .led(led), .seg(seg), .an(an), .dp(dp)
    );

    always #5 clk = ~clk;   // 100 MHz

    // Independent decoder for the board's reply
    initial begin : cap_tx
        logic [7:0] b;
        forever begin
            @(negedge RsTx);
            repeat (CPB + CPB / 2) @(posedge clk);
            for (int i = 0; i < 8; i++) begin
                b[i] = RsTx;
                repeat (CPB) @(posedge clk);
            end
            if (RsTx !== 1'b1) begin
                errors++;
                $display("FAIL: reply had a bad stop bit");
            end
            q_tx.push_back(b);
        end
    end

    // Serial driver (changes on the falling clock edge)
    task automatic send_serial(input logic [7:0] b, input bit bad_stop);
        @(negedge clk); RsRx = 1'b0;  repeat (CPB - 1) @(negedge clk);
        for (int i = 0; i < 8; i++) begin
            @(negedge clk); RsRx = b[i];  repeat (CPB - 1) @(negedge clk);
        end
        @(negedge clk); RsRx = bad_stop ? 1'b0 : 1'b1;  repeat (CPB - 1) @(negedge clk);
        @(negedge clk); RsRx = 1'b1;
    endtask

    task automatic send_image(input int k, input int count);
        for (int i = 0; i < count; i++) send_serial(images[k*N_IN + i], 0);
    endtask

    // Expected display pattern from the letters of the lit segments
    function automatic logic [6:0] expect_seg(input string lit);
        logic [6:0] m = 7'b0;
        for (int i = 0; i < lit.len(); i++) m[lit[i] - "a"] = 1'b1;
        return ~m;
    endfunction

    task automatic expect_int(input string what, input int got, input int exp);
        if (got !== exp) begin
            errors++;
            $display("FAIL: %s = %0d, expected %0d", what, got, exp);
        end
    endtask

    // Wait for the nth reply, then check the reply, display, and LEDs
    task automatic check_result(input int k, input int n_replies, input int n_processed);
        string digit_segs [10];
        int    exp_d;
        logic [7:0] exp_ascii, got_ascii;
        digit_segs = '{"abcdef", "bc", "abdeg", "abcdg", "bcfg",
                       "acdfg", "acdefg", "abc", "abcdefg", "abcdfg"};
        exp_d = exp_pred[k];

        while (q_tx.size() < n_replies) @(negedge clk);
        repeat (20) @(negedge clk);
        expect_int($sformatf("image %0d: replies", k), q_tx.size(), n_replies);
        exp_ascii = 8'(8'h30 + exp_d);
        got_ascii = q_tx[n_replies-1];
        if (got_ascii !== exp_ascii) begin
            errors++;
            $display("FAIL: image %0d: reply %h, expected %h", k, got_ascii, exp_ascii);
        end
        if (seg !== expect_seg(digit_segs[exp_d])) begin
            errors++;
            $display("FAIL: image %0d: display %b does not show %0d", k, seg, exp_d);
        end
        expect_int($sformatf("image %0d: an", k), an, 4'b1110);
        expect_int($sformatf("image %0d: led pred", k), led[3:0], exp_d);
        expect_int($sformatf("image %0d: led count", k), led[11:4], n_processed);
        expect_int($sformatf("image %0d: led result shown", k), led[12], 1);
        expect_int($sformatf("image %0d: led busy", k), led[15], 0);
    endtask

    initial begin
        $readmemh("images.mem",   images);
        $readmemh("exp_pred.mem", exp_pred);

        // power-up reset happens by itself; also press the button
        btnC = 1;
        repeat (10) @(negedge clk);
        btnC = 0;
        repeat (20) @(negedge clk);

        // Before any image: display shows "-", counters are zero, no errors
        if (seg !== expect_seg("g")) begin
            errors++;
            $display("FAIL: display should show '-' after reset, seg=%b", seg);
        end
        expect_int("after reset: led", led, 0);
        expect_int("after reset: idle tx", RsTx, 1);

        // ---- Three normal images ----
        for (int k = 0; k < 3; k++) begin
            send_image(k, N_IN);
            check_result(k, k + 1, k + 1);
        end

        // ---- Framing error in the middle of an image, then recovery ----
        send_image(3, 100);
        send_serial(8'h00, 1);                       // bad stop bit
        repeat (20) @(negedge clk);
        expect_int("after framing error: led[14]", led[14], 1);
        expect_int("after framing error: no reply", q_tx.size(), 3);
        send_image(3, N_IN);                         // a full, clean image must still work
        check_result(3, 4, 4);

        // ---- One more normal image ----
        send_image(4, N_IN);
        check_result(4, 5, 5);
        expect_int("final: framing error stays flagged", led[14], 1);
        expect_int("final: no overrun", led[13], 0);

        if (errors == 0) $display("PASS: board_top end-to-end, 5 images classified over UART");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
