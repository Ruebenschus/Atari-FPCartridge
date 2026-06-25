module cart_rom(
    input  wire        clk,
    input  wire [14:0] addr,
    input  wire        diag_rom_enable,
    input  wire        beep_on,
    output reg  [15:0] data
);

    reg [15:0] image_rom [0:32767];
    reg [15:0] image_data = 16'h4E71;

    initial begin
        $readmemh("build/cart_rom.mem", image_rom);
    end

    always @(posedge clk) begin
        image_data <= image_rom[addr];
    end

    always @(*) begin
        data = image_data;

        if (diag_rom_enable) begin
            case (addr)
                // Diagnostic Cartridge Magic: $FA52235F
                15'h0000: data = 16'hFA52;
                15'h0001: data = 16'h235F;

                // move.w #$2700,sr
                15'h0002: data = 16'h007C;
                15'h0003: data = 16'h2700;

                // move.b #0,$FF8800
                15'h0004: data = 16'h13FC;
                15'h0005: data = 16'h0000;
                15'h0006: data = 16'h00FF;
                15'h0007: data = 16'h8800;

                // move.b #$80,$FF8802
                15'h0008: data = 16'h13FC;
                15'h0009: data = 16'h0080;
                15'h000A: data = 16'h00FF;
                15'h000B: data = 16'h8802;

                // move.b #1,$FF8800
                15'h000C: data = 16'h13FC;
                15'h000D: data = 16'h0001;
                15'h000E: data = 16'h00FF;
                15'h000F: data = 16'h8800;

                // move.b #1,$FF8802
                15'h0010: data = 16'h13FC;
                15'h0011: data = 16'h0001;
                15'h0012: data = 16'h00FF;
                15'h0013: data = 16'h8802;

                // move.b #7,$FF8800
                15'h0014: data = 16'h13FC;
                15'h0015: data = 16'h0007;
                15'h0016: data = 16'h00FF;
                15'h0017: data = 16'h8800;

                // move.b #$3E,$FF8802
                15'h0018: data = 16'h13FC;
                15'h0019: data = 16'h003E;
                15'h001A: data = 16'h00FF;
                15'h001B: data = 16'h8802;

                // poll_loop: move.w $FA0080,d0
                15'h001C: data = 16'h3039;
                15'h001D: data = 16'h00FA;
                15'h001E: data = 16'h0080;

                // beq.s silent
                15'h001F: data = 16'h6712;

                // move.b #8,$FF8800
                15'h0020: data = 16'h13FC;
                15'h0021: data = 16'h0008;
                15'h0022: data = 16'h00FF;
                15'h0023: data = 16'h8800;

                // move.b #15,$FF8802
                15'h0024: data = 16'h13FC;
                15'h0025: data = 16'h000F;
                15'h0026: data = 16'h00FF;
                15'h0027: data = 16'h8802;

                // bra.s poll_loop
                15'h0028: data = 16'h60E6;

                // silent: move.b #8,$FF8800
                15'h0029: data = 16'h13FC;
                15'h002A: data = 16'h0008;
                15'h002B: data = 16'h00FF;
                15'h002C: data = 16'h8800;

                // move.b #0,$FF8802
                15'h002D: data = 16'h13FC;
                15'h002E: data = 16'h0000;
                15'h002F: data = 16'h00FF;
                15'h0030: data = 16'h8802;

                // bra.s poll_loop
                15'h0031: data = 16'h60D4;

                // Mode word polled by the 68k loop.
                // 0 = mute, 1 = beep.
                15'h0040: data = beep_on ? 16'h0001 : 16'h0000;

                default: data = 16'h4E71;
            endcase
        end
    end

endmodule
