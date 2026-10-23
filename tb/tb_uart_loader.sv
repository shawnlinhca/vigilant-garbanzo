// Self-checking testbench for uart_loader.sv.
// Bytes are fed directly (valid pulses), not through a serial line.
// Tests: a full image (and that `start` fires only after the last write landed),
// a framing error mid-image, a timeout mid-image, and a byte while the network is busy.
`timescale 1ns / 1ps

module tb_uart_loader;
    localparam int N       = 784;
    localparam int TIMEOUT = 200;

    logic       clk = 1'b0;
    logic       rst;
    logic [7:0] rx_data;
    logic       rx_valid, rx_frame_err, net_busy;
    logic       img_we, start, err_frame, err_overrun;
    logic [9:0] img_waddr;
    logic [7:0] img_wdata;

    logic [7:0] mem [N];          // model of the network's image memory
    int  wr_count = 0, start_count = 0;
    int  errors = 0;
    logic [7:0] last_at_start;

    uart_loader #(.N_BYTES(N), .TIMEOUT_CLKS(TIMEOUT)) dut (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_frame_err),
        .net_busy(net_busy),
        .img_we(img_we), .img_waddr(img_waddr), .img_wdata(img_wdata), .start(start),
        .err_frame(err_frame), .err_overrun(err_overrun)
    );

    always #5 clk = ~clk;

    // Memory model and start monitor
    always @(posedge clk) begin
        if (img_we) begin
            mem[img_waddr] <= img_wdata;
            wr_count++;
        end
        if (start) begin
            start_count++;
            last_at_start <= mem[N-1];   // the final byte must already be in memory
        end
    end

    function automatic logic [7:0] pat(input int img, input int i);
        return 8'(i * 7 + img * 31 + 3);
    endfunction

    task automatic send_byte(input logic [7:0] b);
        @(negedge clk); rx_data = b; rx_valid = 1;
        @(negedge clk); rx_valid = 0;
        repeat (3) @(negedge clk);
    endtask

    task automatic send_ferr();
        @(negedge clk); rx_frame_err = 1;
        @(negedge clk); rx_frame_err = 0;
        repeat (3) @(negedge clk);
    endtask

    task automatic send_image(input int img, input int count);
        for (int i = 0; i < count; i++) send_byte(pat(img, i));
    endtask

    task automatic check_image(input string what, input int img);
        int bad = 0;
        for (int i = 0; i < N; i++) if (mem[i] !== pat(img, i)) bad++;
        if (bad != 0) begin
            errors++;
            $display("FAIL: %s: %0d of %0d bytes wrong in memory", what, bad, N);
        end
    endtask

    task automatic expect_int(input string what, input int got, input int exp);
        if (got !== exp) begin
            errors++;
            $display("FAIL: %s = %0d, expected %0d", what, got, exp);
        end
    endtask

    initial begin
        int wr_before;
        rst = 1; rx_data = 0; rx_valid = 0; rx_frame_err = 0; net_busy = 0;
        repeat (5) @(negedge clk);
        rst = 0;
        repeat (3) @(negedge clk);

        // ---- Test 1: one full image ----
        send_image(0, N);
        repeat (5) @(negedge clk);
        expect_int("t1: writes", wr_count, N);
        expect_int("t1: starts", start_count, 1);
        check_image("t1", 0);
        if (last_at_start !== pat(0, N-1)) begin
            errors++;
            $display("FAIL: t1: start fired before the last byte was in memory");
        end
        expect_int("t1: err_frame", err_frame, 0);
        expect_int("t1: err_overrun", err_overrun, 0);

        // ---- Test 2: framing error mid-image -> discard, next full image is intact ----
        send_image(1, 100);
        send_ferr();
        send_image(2, N);
        repeat (5) @(negedge clk);
        expect_int("t2: starts", start_count, 2);
        check_image("t2", 2);
        expect_int("t2: err_frame", err_frame, 1);

        // ---- Test 3: stall mid-image -> timeout discards it ----
        send_image(3, 50);
        repeat (TIMEOUT + 100) @(negedge clk);
        send_image(4, N);
        repeat (5) @(negedge clk);
        expect_int("t3: starts", start_count, 3);
        check_image("t3", 4);

        // ---- Test 4: byte while the network is busy -> dropped, partial image discarded ----
        send_image(5, 10);
        wr_before = wr_count;
        net_busy = 1;
        send_byte(8'hEE);
        net_busy = 0;
        expect_int("t4: writes during busy", wr_count, wr_before);
        expect_int("t4: err_overrun", err_overrun, 1);
        send_image(6, N);
        repeat (5) @(negedge clk);
        expect_int("t4: starts", start_count, 4);
        check_image("t4", 6);

        if (errors == 0) $display("PASS: all UART loader tests passed");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #100_000_000;
        $display("FAIL: timeout");
        $finish;
    end
endmodule
