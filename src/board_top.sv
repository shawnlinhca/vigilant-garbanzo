// Basys 3 top level: UART in -> loader -> network -> display + UART out.
//
//   PC --RsRx--> uart_rx -> uart_loader -> network (784-32-10) --> pred
//   pred -> seven-segment display, LEDs, and back to the PC as an ASCII digit via uart_tx
//
// Protocol: send 784 raw pixel bytes (0..255, row-major) at 115200 baud, 8N1.
// The board replies with one ASCII character '0'..'9'.
//
// LEDs: [3:0] last prediction, [11:4] images processed (wraps at 256), [12] result shown,
//       [13] overrun error, [14] framing error, [15] network busy.
// Button btnC = reset (also cleared automatically at power-up).
module board_top #(
    parameter int CLKS_PER_BIT = 868,            // 100 MHz / 115200
    parameter int TIMEOUT_CLKS = 10_000_000      // 0.1 s: discard a stalled partial image
) (
    input  logic        clk,                     // 100 MHz
    input  logic        btnC,                    // reset
    input  logic        RsRx,                    // USB-UART: PC -> FPGA
    output logic        RsTx,                    // USB-UART: FPGA -> PC
    output logic [15:0] led,
    output logic [6:0]  seg,
    output logic [3:0]  an,
    output logic        dp
);
    // ---- Reset: synchronized button, plus a short power-up reset ----
    logic [1:0] btn_ff;
    logic [3:0] por = 4'd0;                      // registers power up at their initial values
    always_ff @(posedge clk) begin
        btn_ff <= {btn_ff[0], btnC};
        if (!por[3]) por <= por + 1'b1;
    end
    logic rst;
    assign rst = btn_ff[1] | ~por[3];

    // ---- UART receive and image loading ----
    logic [7:0] rx_data;
    logic       rx_valid, rx_ferr;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk), .rst(rst), .rx(RsRx),
        .data(rx_data), .valid(rx_valid), .frame_err(rx_ferr)
    );

    logic       img_we, start, err_frame, err_overrun, net_busy;
    logic [9:0] img_waddr;
    logic [7:0] img_wdata;
    uart_loader #(.N_BYTES(784), .TIMEOUT_CLKS(TIMEOUT_CLKS)) u_loader (
        .clk(clk), .rst(rst),
        .rx_data(rx_data), .rx_valid(rx_valid), .rx_frame_err(rx_ferr),
        .net_busy(net_busy),
        .img_we(img_we), .img_waddr(img_waddr), .img_wdata(img_wdata), .start(start),
        .err_frame(err_frame), .err_overrun(err_overrun)
    );

    // ---- The neural network ----
    logic       net_done;
    logic [3:0] pred;
    network u_net (
        .clk(clk), .rst(rst),
        .img_we(img_we), .img_waddr(img_waddr), .img_wdata(img_wdata),
        .start(start), .busy(net_busy), .done(net_done), .pred(pred)
    );

    // ---- Latch the result, count images, trigger the reply ----
    logic [3:0] pred_q;
    logic       have_result, tx_send;
    logic [7:0] img_count;
    always_ff @(posedge clk) begin
        if (rst) begin
            pred_q      <= '0;
            have_result <= 1'b0;
            img_count   <= '0;
            tx_send     <= 1'b0;
        end else begin
            tx_send <= net_done;                 // pred_q is updated on the same edge
            if (start) have_result <= 1'b0;      // display "-" while computing
            if (net_done) begin
                pred_q      <= pred;
                have_result <= 1'b1;
                img_count   <= img_count + 1'b1;
            end
        end
    end

    // ---- Reply to the PC: ASCII '0'..'9' ----
    logic [7:0] tx_data;
    logic       tx_busy;
    assign tx_data = 8'h30 + {4'b0000, pred_q};
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk), .rst(rst), .data(tx_data), .send(tx_send), .busy(tx_busy), .tx(RsTx)
    );

    // ---- Display and LEDs ----
    seg7 u_seg (.digit(pred_q), .show(have_result), .seg(seg), .an(an), .dp(dp));

    assign led = {net_busy, err_frame, err_overrun, have_result, img_count, pred_q};
endmodule
