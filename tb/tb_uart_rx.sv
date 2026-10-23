// Self-checking testbench for uart_rx.sv.
// Two receivers run side by side: a fast one (16 clocks per bit) for thorough tests, and
// one at the real 868 clocks per bit (115200 baud at 100 MHz) for a few bytes.
// Tests: all 256 byte values sent back-to-back, a bad stop bit, a short glitch.
`timescale 1ns / 1ps

module tb_uart_rx;
    localparam int FAST_CPB = 16;
    localparam int REAL_CPB = 868;

    logic clk = 1'b0;
    logic rst;
    logic rx_f = 1'b1, rx_r = 1'b1;
    logic [7:0] data_f, data_r;
    logic valid_f, valid_r, ferr_f, ferr_r;

    logic [7:0] q_f [$];
    logic [7:0] q_r [$];
    int fe_f = 0, fe_r = 0;
    int errors = 0;

    uart_rx #(.CLKS_PER_BIT(FAST_CPB)) u_fast (
        .clk(clk), .rst(rst), .rx(rx_f), .data(data_f), .valid(valid_f), .frame_err(ferr_f));
    uart_rx #(.CLKS_PER_BIT(REAL_CPB)) u_real (
        .clk(clk), .rst(rst), .rx(rx_r), .data(data_r), .valid(valid_r), .frame_err(ferr_r));

    always #5 clk = ~clk;   // 100 MHz

    always @(posedge clk) begin
        if (valid_f) q_f.push_back(data_f);
        if (ferr_f)  fe_f++;
        if (valid_r) q_r.push_back(data_r);
        if (ferr_r)  fe_r++;
    end

    // Inputs change on the falling clock edge, away from the receiver's sampling edge.
    task automatic drive(input bit is_fast, input logic v);
        if (is_fast) rx_f = v; else rx_r = v;
    endtask

    task automatic wait_clks(input int n);
        repeat (n) @(negedge clk);
    endtask

    task automatic send(input bit is_fast, input logic [7:0] b, input int cpb,
                        input bit bad_stop);
        drive(is_fast, 1'b0);  wait_clks(cpb);                       // start bit
        for (int i = 0; i < 8; i++) begin
            drive(is_fast, b[i]);  wait_clks(cpb);                   // data bits, LSB first
        end
        drive(is_fast, bad_stop ? 1'b0 : 1'b1);  wait_clks(cpb);     // stop bit
        drive(is_fast, 1'b1);                                        // back to idle
    endtask

    task automatic expect_int(input string what, input int got, input int exp);
        if (got !== exp) begin
            errors++;
            $display("FAIL: %s = %0d, expected %0d", what, got, exp);
        end
    endtask

    initial begin
        logic [7:0] real_bytes [4];
        logic [7:0] exp_b;
        real_bytes = '{8'hA5, 8'h00, 8'hFF, 8'h5A};

        rst = 1;
        wait_clks(5);
        rst = 0;
        wait_clks(5);

        // ---- Test 1: all 256 values, back-to-back (no idle gap between bytes) ----
        for (int v = 0; v < 256; v++) send(1, v[7:0], FAST_CPB, 0);
        wait_clks(4 * FAST_CPB);
        expect_int("fast: bytes received", q_f.size(), 256);
        for (int v = 0; v < q_f.size() && v < 256; v++) begin
            exp_b = 8'(v);
            if (q_f[v] !== exp_b) begin
                errors++;
                if (errors <= 10)
                    $display("FAIL: fast byte %0d received as %h, expected %h", v, q_f[v], exp_b);
            end
        end
        expect_int("fast: framing errors after clean traffic", fe_f, 0);

        // ---- Test 2: bad stop bit -> no byte, one framing error ----
        q_f.delete();
        send(1, 8'h55, FAST_CPB, 1);
        wait_clks(4 * FAST_CPB);
        expect_int("fast: bytes after bad stop", q_f.size(), 0);
        expect_int("fast: framing errors after bad stop", fe_f, 1);

        // ---- Test 3: next good byte is still received (receiver recovered) ----
        send(1, 8'h3C, FAST_CPB, 0);
        wait_clks(4 * FAST_CPB);
        expect_int("fast: bytes after recovery", q_f.size(), 1);
        if (q_f.size() == 1 && q_f[0] !== 8'h3C) begin
            errors++;
            $display("FAIL: recovery byte received as %h", q_f[0]);
        end

        // ---- Test 4: glitch shorter than half a bit is ignored ----
        q_f.delete();
        drive(1, 1'b0);  wait_clks(FAST_CPB / 4);  drive(1, 1'b1);
        wait_clks(4 * FAST_CPB);
        expect_int("fast: bytes after glitch", q_f.size(), 0);
        expect_int("fast: framing errors after glitch", fe_f, 1);   // unchanged

        // ---- Test 5: real baud rate (868 clocks per bit) ----
        for (int i = 0; i < 4; i++) send(0, real_bytes[i], REAL_CPB, 0);
        wait_clks(4 * REAL_CPB);
        expect_int("real: bytes received", q_r.size(), 4);
        for (int i = 0; i < q_r.size() && i < 4; i++) begin
            if (q_r[i] !== real_bytes[i]) begin
                errors++;
                $display("FAIL: real byte %0d received as %h, expected %h", i, q_r[i], real_bytes[i]);
            end
        end
        expect_int("real: framing errors", fe_r, 0);

        if (errors == 0) $display("PASS: all UART receiver tests passed");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
