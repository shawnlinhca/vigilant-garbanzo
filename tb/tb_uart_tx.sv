// Self-checking testbench for uart_tx.sv.
// An independent decoder in the testbench (not uart_rx) watches the line: it finds the
// falling edge, samples every bit at its midpoint, and checks the stop bit.
// Also checks busy lasts exactly 10 bit times per byte and that `send` while busy is ignored.
// Two transmitters: fast (16 clocks per bit) for all 256 values, real (868) for a few.
`timescale 1ns / 1ps

module tb_uart_tx;
    localparam int FAST_CPB = 16;
    localparam int REAL_CPB = 868;

    logic clk = 1'b0;
    logic rst;
    logic [7:0] data_f, data_r;
    logic send_f, send_r;
    logic tx_f, tx_r, busy_f, busy_r;

    logic [7:0] q_f [$];
    logic [7:0] q_r [$];
    int stop_bad_f = 0, stop_bad_r = 0;
    int busy_cycles_f = 0, busy_cycles_r = 0;
    int errors = 0;

    uart_tx #(.CLKS_PER_BIT(FAST_CPB)) u_fast (
        .clk(clk), .rst(rst), .data(data_f), .send(send_f), .busy(busy_f), .tx(tx_f));
    uart_tx #(.CLKS_PER_BIT(REAL_CPB)) u_real (
        .clk(clk), .rst(rst), .data(data_r), .send(send_r), .busy(busy_r), .tx(tx_r));

    always #5 clk = ~clk;   // 100 MHz

    always @(posedge clk) begin
        if (busy_f) busy_cycles_f++;
        if (busy_r) busy_cycles_r++;
    end

    // Independent decoders: sample each bit at its midpoint
    initial begin : cap_fast
        logic [7:0] b;
        forever begin
            @(negedge tx_f);
            repeat (FAST_CPB + FAST_CPB / 2) @(posedge clk);
            for (int i = 0; i < 8; i++) begin
                b[i] = tx_f;
                repeat (FAST_CPB) @(posedge clk);
            end
            if (tx_f !== 1'b1) stop_bad_f++;
            q_f.push_back(b);
        end
    end

    initial begin : cap_real
        logic [7:0] b;
        forever begin
            @(negedge tx_r);
            repeat (REAL_CPB + REAL_CPB / 2) @(posedge clk);
            for (int i = 0; i < 8; i++) begin
                b[i] = tx_r;
                repeat (REAL_CPB) @(posedge clk);
            end
            if (tx_r !== 1'b1) stop_bad_r++;
            q_r.push_back(b);
        end
    end

    task automatic send_byte(input bit is_fast, input logic [7:0] b);
        @(negedge clk);
        if (is_fast) begin data_f = b; send_f = 1'b1; end
        else         begin data_r = b; send_r = 1'b1; end
        @(negedge clk);
        if (is_fast) send_f = 1'b0; else send_r = 1'b0;
        if (is_fast) begin
            wait (!busy_f);
        end else begin
            wait (!busy_r);
        end
    endtask

    task automatic expect_int(input string what, input int got, input int exp);
        if (got !== exp) begin
            errors++;
            $display("FAIL: %s = %0d, expected %0d", what, got, exp);
        end
    endtask

    initial begin
        logic [7:0] exp_b;

        rst = 1; send_f = 0; send_r = 0; data_f = 0; data_r = 0;
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (3) @(negedge clk);

        expect_int("fast: idle tx level", tx_f, 1);
        expect_int("fast: idle busy", busy_f, 0);

        // ---- Test 1: all 256 values, one after another ----
        for (int v = 0; v < 256; v++) send_byte(1, 8'(v));
        repeat (4 * FAST_CPB) @(negedge clk);
        expect_int("fast: bytes sent", q_f.size(), 256);
        for (int v = 0; v < q_f.size() && v < 256; v++) begin
            exp_b = 8'(v);
            if (q_f[v] !== exp_b) begin
                errors++;
                if (errors <= 10)
                    $display("FAIL: fast byte %0d decoded as %h, expected %h", v, q_f[v], exp_b);
            end
        end
        expect_int("fast: bad stop bits", stop_bad_f, 0);
        expect_int("fast: total busy cycles", busy_cycles_f, 256 * 10 * FAST_CPB);

        // ---- Test 2: `send` while busy is ignored ----
        q_f.delete();
        busy_cycles_f = 0;
        @(negedge clk); data_f = 8'hA5; send_f = 1;
        @(negedge clk); send_f = 0;
        repeat (3 * FAST_CPB) @(negedge clk);          // mid-frame
        data_f = 8'h5A; send_f = 1;
        @(negedge clk); send_f = 0;
        wait (!busy_f);
        repeat (4 * FAST_CPB) @(negedge clk);
        expect_int("fast: bytes after ignored send", q_f.size(), 1);
        if (q_f.size() >= 1 && q_f[0] !== 8'hA5) begin
            errors++;
            $display("FAIL: first byte decoded as %h, expected a5", q_f[0]);
        end
        expect_int("fast: busy cycles for one frame", busy_cycles_f, 10 * FAST_CPB);

        // ---- Test 3: real baud rate (868 clocks per bit) ----
        send_byte(0, 8'hA5);
        send_byte(0, 8'h3C);
        repeat (4 * REAL_CPB) @(negedge clk);
        expect_int("real: bytes sent", q_r.size(), 2);
        if (q_r.size() >= 2) begin
            if (q_r[0] !== 8'hA5) begin errors++; $display("FAIL: real byte 0 decoded as %h", q_r[0]); end
            if (q_r[1] !== 8'h3C) begin errors++; $display("FAIL: real byte 1 decoded as %h", q_r[1]); end
        end
        expect_int("real: bad stop bits", stop_bad_r, 0);
        expect_int("real: total busy cycles", busy_cycles_r, 2 * 10 * REAL_CPB);

        if (errors == 0) $display("PASS: all UART transmitter tests passed");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #400_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
