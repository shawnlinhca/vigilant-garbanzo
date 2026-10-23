// Loads an image from the UART into the network and starts it.
//
// Protocol: the PC sends exactly N_BYTES raw pixel bytes (784 for MNIST), no header.
// Each byte is written to the network's image memory at the next address; one cycle
// after the final write lands, `start` pulses for one clock.
//
// Error handling (a lost byte would otherwise shift every later image):
//   - framing error from the receiver: discard the partial image, set err_frame
//   - no byte for TIMEOUT_CLKS while an image is partly received: discard it (the PC
//     sender pauses between images while it waits for the answer, so this resyncs)
//   - byte arrives while the network is busy: drop it, discard the partial image,
//     set err_overrun
// err_frame and err_overrun stay set until reset.
module uart_loader #(
    parameter int N_BYTES      = 784,
    parameter int TIMEOUT_CLKS = 10_000_000       // 0.1 s at 100 MHz
) (
    input  logic       clk,
    input  logic       rst,
    // from uart_rx
    input  logic [7:0] rx_data,
    input  logic       rx_valid,
    input  logic       rx_frame_err,
    // from the network
    input  logic       net_busy,
    // to the network
    output logic       img_we,
    output logic [9:0] img_waddr,
    output logic [7:0] img_wdata,
    output logic       start,
    // status
    output logic       err_frame,
    output logic       err_overrun
);
    localparam int AW = $clog2(N_BYTES);
    localparam int TW = $clog2(TIMEOUT_CLKS + 1);

    logic [AW-1:0] cnt;          // next byte index (0 = no image in progress)
    logic          last_q;       // the final byte of an image was just written
    logic [TW-1:0] idle_cnt;     // clocks since the last byte of a partial image

    always_ff @(posedge clk) begin
        img_we <= 1'b0;
        start  <= 1'b0;
        if (rst) begin
            cnt         <= '0;
            last_q      <= 1'b0;
            idle_cnt    <= '0;
            img_waddr   <= '0;
            img_wdata   <= '0;
            err_frame   <= 1'b0;
            err_overrun <= 1'b0;
        end else begin
            start  <= last_q;    // one cycle after the final write was issued
            last_q <= 1'b0;

            if (rx_frame_err) begin
                cnt       <= '0;
                idle_cnt  <= '0;
                err_frame <= 1'b1;
            end else if (rx_valid) begin
                idle_cnt <= '0;
                if (net_busy) begin
                    cnt         <= '0;
                    err_overrun <= 1'b1;
                end else begin
                    img_we    <= 1'b1;
                    img_waddr <= 10'(cnt);
                    img_wdata <= rx_data;
                    if (cnt == N_BYTES - 1) begin
                        cnt    <= '0;
                        last_q <= 1'b1;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end
            end else if (cnt != 0) begin
                if (idle_cnt == TIMEOUT_CLKS - 1) begin
                    cnt      <= '0;
                    idle_cnt <= '0;
                end else begin
                    idle_cnt <= idle_cnt + 1'b1;
                end
            end
        end
    end
endmodule
