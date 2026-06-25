module button_edge(
    input  wire clk,
    input  wire btn_in,
    output reg  pulse
);

    localparam [17:0] DEBOUNCE_TICKS = 18'd250_000; // 10 ms @ 25 MHz

    reg btn_meta = 1'b0;
    reg btn_sync = 1'b0;
    reg btn_state = 1'b0;
    reg [17:0] debounce_cnt = 18'd0;

    always @(posedge clk) begin
        btn_meta <= btn_in;
        btn_sync <= btn_meta;
        pulse <= 1'b0;

        if (btn_sync == btn_state) begin
            debounce_cnt <= 18'd0;
        end else begin
            if (debounce_cnt == DEBOUNCE_TICKS) begin
                btn_state <= btn_sync;
                debounce_cnt <= 18'd0;
                pulse <= btn_sync;
            end else begin
                debounce_cnt <= debounce_cnt + 18'd1;
            end
        end
    end

endmodule
