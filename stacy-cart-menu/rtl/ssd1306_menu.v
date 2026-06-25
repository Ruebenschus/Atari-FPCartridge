module ssd1306_menu #(
    parameter integer CLK_HZ    = 25000000,
    parameter integer I2C_HZ    = 100000,
    parameter [6:0]   OLED_ADDR = 7'h3C
)(
    input  wire       clk,
    input  wire [1:0] main_selected,
    input  wire [1:0] cart_selected,
    input  wire       debug_selected,
    input  wire [2:0] view_mode,
    input  wire [1:0] cart_mode,
    input  wire       boot_magic_ok,
    input  wire       boot_code_ok,
    input  wire       boot_idle_ok,
    input  wire       usb_power,
    input  wire [4:0] drive_index,
    input  wire       drive_level,
    input  wire [5:0] read_index,
    input  wire       read_value,
    input  wire       test_io_in,
    input  wire [14:0] current_addr,
    input  wire [14:0] trace_addr0,
    input  wire [14:0] trace_addr1,
    input  wire [14:0] trace_addr2,
    input  wire [14:0] trace_addr3,

    inout  wire       scl,
    inout  wire       sda
);

    localparam integer I2C_DIV = CLK_HZ / (I2C_HZ * 4);
    localparam integer POWERON_WAIT = CLK_HZ / 5; // 200 ms
    localparam [7:0] GLYPH_CHECK = 8'h7E;
    localparam [1:0] CART_DIAG    = 2'd0;
    localparam [1:0] CART_BEEP    = 2'd1;
    localparam [1:0] CART_ROMTEST = 2'd2;
    localparam [2:0] VIEW_MENU       = 3'd0;
    localparam [2:0] VIEW_CART_MENU  = 3'd1;
    localparam [2:0] VIEW_DEBUG_MENU = 3'd2;
    localparam [2:0] VIEW_DIAG       = 3'd3;
    localparam [2:0] VIEW_DRIVE      = 3'd4;
    localparam [2:0] VIEW_READ       = 3'd5;

    wire diag_view = (view_mode == VIEW_DIAG);

    reg scl_low = 1'b0;
    reg sda_low = 1'b0;

    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;

    reg        tx_start = 1'b0;
    reg        tx_busy  = 1'b0;
    reg        tx_done  = 1'b0;
    reg [7:0]  tx_ctrl  = 8'h00;
    reg [7:0]  tx_data  = 8'h00;

    reg [7:0]  lat_ctrl = 8'h00;
    reg [7:0]  lat_data = 8'h00;

    reg [15:0] divcnt   = 16'd0;
    reg [3:0]  tx_state = 4'd0;
    reg [1:0]  byte_idx = 2'd0;
    reg [2:0]  bit_idx  = 3'd7;
    reg [7:0]  cur_byte = 8'h00;

    always @(*) begin
        case (byte_idx)
            2'd0: cur_byte = {OLED_ADDR, 1'b0};
            2'd1: cur_byte = lat_ctrl;
            default: cur_byte = lat_data;
        endcase
    end

    always @(posedge clk) begin
        tx_done <= 1'b0;

        if (!tx_busy) begin
            scl_low <= 1'b0;
            sda_low <= 1'b0;
            divcnt  <= 16'd0;

            if (tx_start) begin
                tx_busy  <= 1'b1;
                tx_state <= 4'd1;
                byte_idx <= 2'd0;
                bit_idx  <= 3'd7;
                lat_ctrl <= tx_ctrl;
                lat_data <= tx_data;
            end
        end else begin
            if (divcnt != I2C_DIV-1) begin
                divcnt <= divcnt + 16'd1;
            end else begin
                divcnt <= 16'd0;

                case (tx_state)
                    4'd1: begin
                        sda_low <= 1'b1;
                        scl_low <= 1'b0;
                        tx_state <= 4'd2;
                    end

                    4'd2: begin
                        scl_low <= 1'b1;
                        sda_low <= ~cur_byte[bit_idx];
                        tx_state <= 4'd3;
                    end

                    4'd3: begin
                        scl_low <= 1'b0;
                        tx_state <= 4'd4;
                    end

                    4'd4: begin
                        scl_low <= 1'b1;

                        if (bit_idx == 3'd0) begin
                            sda_low <= 1'b0;
                            tx_state <= 4'd5;
                        end else begin
                            bit_idx <= bit_idx - 3'd1;
                            sda_low <= ~cur_byte[bit_idx - 3'd1];
                            tx_state <= 4'd3;
                        end
                    end

                    4'd5: begin
                        scl_low <= 1'b0;
                        tx_state <= 4'd6;
                    end

                    4'd6: begin
                        scl_low <= 1'b1;

                        if (byte_idx == 2'd2) begin
                            sda_low <= 1'b1;
                            tx_state <= 4'd7;
                        end else begin
                            byte_idx <= byte_idx + 2'd1;
                            bit_idx <= 3'd7;
                            tx_state <= 4'd2;
                        end
                    end

                    4'd7: begin
                        scl_low <= 1'b0;
                        sda_low <= 1'b1;
                        tx_state <= 4'd8;
                    end

                    4'd8: begin
                        sda_low <= 1'b0;
                        tx_busy <= 1'b0;
                        tx_done <= 1'b1;
                        tx_state <= 4'd0;
                    end

                    default: begin
                        tx_busy <= 1'b0;
                        tx_state <= 4'd0;
                    end
                endcase
            end
        end
    end

    function [7:0] init_cmd;
        input [5:0] idx;
        begin
            case (idx)
                6'd0:  init_cmd = 8'hAE;
                6'd1:  init_cmd = 8'hD5;
                6'd2:  init_cmd = 8'h80;
                6'd3:  init_cmd = 8'hA8;
                6'd4:  init_cmd = 8'h3F;
                6'd5:  init_cmd = 8'hD3;
                6'd6:  init_cmd = 8'h00;
                6'd7:  init_cmd = 8'h40;
                6'd8:  init_cmd = 8'h8D;
                6'd9:  init_cmd = 8'h14;
                6'd10: init_cmd = 8'h20;
                6'd11: init_cmd = 8'h02;
				6'd12: init_cmd = 8'hA0;
				6'd13: init_cmd = 8'hC0;
                6'd14: init_cmd = 8'hDA;
                6'd15: init_cmd = 8'h12;
                6'd16: init_cmd = 8'h81;
                6'd17: init_cmd = 8'hCF;
                6'd18: init_cmd = 8'hD9;
                6'd19: init_cmd = 8'hF1;
                6'd20: init_cmd = 8'hDB;
                6'd21: init_cmd = 8'h40;
                6'd22: init_cmd = 8'hA4;
                6'd23: init_cmd = 8'hA6;
                6'd24: init_cmd = 8'h2E;
                6'd25: init_cmd = 8'hAF;
                default: init_cmd = 8'hAF;
            endcase
        end
    endfunction

    function [7:0] hex_char;
        input [3:0] nibble;
        begin
            case (nibble)
                4'h0: hex_char = "0";
                4'h1: hex_char = "1";
                4'h2: hex_char = "2";
                4'h3: hex_char = "3";
                4'h4: hex_char = "4";
                4'h5: hex_char = "5";
                4'h6: hex_char = "6";
                4'h7: hex_char = "7";
                4'h8: hex_char = "8";
                4'h9: hex_char = "9";
                4'hA: hex_char = "A";
                4'hB: hex_char = "B";
                4'hC: hex_char = "C";
                4'hD: hex_char = "D";
                4'hE: hex_char = "E";
                default: hex_char = "F";
            endcase
        end
    endfunction

    function [7:0] addr_char;
        input [14:0] addr;
        input [1:0] digit;
        begin
            case (digit)
                2'd0: addr_char = hex_char({1'b0, addr[14:12]});
                2'd1: addr_char = hex_char(addr[11:8]);
                2'd2: addr_char = hex_char(addr[7:4]);
                default: addr_char = hex_char(addr[3:0]);
            endcase
        end
    endfunction

    function [7:0] dec_char;
        input [3:0] val;
        begin
            case (val)
                4'd0: dec_char = "0";
                4'd1: dec_char = "1";
                4'd2: dec_char = "2";
                4'd3: dec_char = "3";
                4'd4: dec_char = "4";
                4'd5: dec_char = "5";
                4'd6: dec_char = "6";
                4'd7: dec_char = "7";
                4'd8: dec_char = "8";
                default: dec_char = "9";
            endcase
        end
    endfunction

    function [7:0] drive_name_char;
        input [4:0] idx;
        input [3:0] pos;
        reg [4:0] ones;
        begin
            ones = (idx >= 5'd10) ? (idx - 5'd10) : idx;
            case (pos)
                0: drive_name_char = "D";
                1: drive_name_char = (idx >= 5'd10) ? "1" : "0";
                2: drive_name_char = dec_char(ones[3:0]);
                default: drive_name_char = " ";
            endcase
        end
    endfunction

    function [7:0] read_name_char;
        input [5:0] idx;
        input [3:0] pos;
        reg [4:0] ones;
        reg [4:0] addr_num;
        reg [4:0] data_num;
        begin
            addr_num = idx[4:0] + 5'd1;
            data_num = idx[4:0] - 5'd15;
            ones = (addr_num >= 5'd10) ? (addr_num - 5'd10) : addr_num;

            if (idx <= 6'd14) begin
                case (pos)
                    0: read_name_char = "A";
                    1: read_name_char = (addr_num >= 5'd10) ? "1" : "0";
                    2: read_name_char = dec_char(ones[3:0]);
                    default: read_name_char = " ";
                endcase
            end else if (idx <= 6'd30) begin
                case (pos)
                    0: read_name_char = "D";
                    1: read_name_char = (data_num >= 5'd10) ? "1" : "0";
                    2: read_name_char = dec_char((data_num >= 5'd10) ? (data_num - 5'd10) : data_num[3:0]);
                    default: read_name_char = " ";
                endcase
            end else if (idx == 6'd31) begin
                case (pos)
                    0: read_name_char = "R";
                    1: read_name_char = "O";
                    2: read_name_char = "M";
                    3: read_name_char = "3";
                    default: read_name_char = " ";
                endcase
            end else if (idx == 6'd32) begin
                case (pos)
                    0: read_name_char = "R";
                    1: read_name_char = "O";
                    2: read_name_char = "M";
                    3: read_name_char = "4";
                    default: read_name_char = " ";
                endcase
            end else if (idx == 6'd33) begin
                case (pos)
                    0: read_name_char = "U";
                    1: read_name_char = "D";
                    2: read_name_char = "S";
                    3: read_name_char = "n";
                    default: read_name_char = " ";
                endcase
            end else if (idx == 6'd34) begin
                case (pos)
                    0: read_name_char = "L";
                    1: read_name_char = "D";
                    2: read_name_char = "S";
                    3: read_name_char = "n";
                    default: read_name_char = " ";
                endcase
            end else begin
                read_name_char = " ";
            end
        end
    endfunction

    function [7:0] cart_mode_char;
        input [1:0] mode;
        input [3:0] pos;
        begin
            case (mode)
                CART_DIAG: begin
                    case (pos)
                        0: cart_mode_char = "b";
                        1: cart_mode_char = "o";
                        2: cart_mode_char = "o";
                        3: cart_mode_char = "t";
                        4: cart_mode_char = "_";
                        5: cart_mode_char = "a";
                        6: cart_mode_char = "n";
                        7: cart_mode_char = "a";
                        8: cart_mode_char = "l";
                        9: cart_mode_char = "y";
                        10: cart_mode_char = "z";
                        11: cart_mode_char = "e";
                        12: cart_mode_char = "r";
                        default: cart_mode_char = " ";
                    endcase
                end
                CART_BEEP: begin
                    case (pos)
                        0: cart_mode_char = "b";
                        1: cart_mode_char = "e";
                        2: cart_mode_char = "e";
                        3: cart_mode_char = "p";
                        default: cart_mode_char = " ";
                    endcase
                end
                default: begin
                    case (pos)
                        0: cart_mode_char = "d";
                        1: cart_mode_char = "i";
                        2: cart_mode_char = "a";
                        3: cart_mode_char = "g";
                        4: cart_mode_char = "_";
                        5: cart_mode_char = "c";
                        6: cart_mode_char = "a";
                        7: cart_mode_char = "r";
                        8: cart_mode_char = "t";
                        default: cart_mode_char = " ";
                    endcase
                end
            endcase
        end
    endfunction

    function [7:0] text_char;
        input [1:0] line;
        input [3:0] pos;
        begin
            text_char = " ";

            if (view_mode == VIEW_MENU) begin
                case (line)
                    2'd0: begin
                        case (pos)
                            0: text_char = " ";
                            1: text_char = " ";
                            2: text_char = " ";
                            3: text_char = "u";
                            4: text_char = "l";
                            5: text_char = "x";
                            6: text_char = "3";
                            7: text_char = "s";
                            8: text_char = "-";
                            9: text_char = "c";
                            10: text_char = "a";
                            11: text_char = "r";
                            12: text_char = "t";
                            default: text_char = " ";
                        endcase
                    end

                    2'd1: begin
                        case (pos)
                            0: text_char = (main_selected == 2'd0) ? ">" : " ";
                            1: text_char = "1";
                            2: text_char = ".";
                            3: text_char = "c";
                            4: text_char = "a";
                            5: text_char = "r";
                            6: text_char = "t";
                            7: text_char = "r";
                            8: text_char = "i";
                            9: text_char = "d";
                            10: text_char = "g";
                            11: text_char = "e";
                            default: text_char = " ";
                        endcase
                    end

                    2'd2: begin
                        case (pos)
                            0: text_char = (main_selected == 2'd1) ? ">" : " ";
                            1: text_char = "2";
                            2: text_char = ".";
                            3: text_char = "c";
                            4: text_char = "a";
                            5: text_char = "r";
                            6: text_char = "t";
                            7: text_char = "-";
                            8: text_char = "d";
                            9: text_char = "e";
                            10: text_char = "b";
                            11: text_char = "u";
                            12: text_char = "g";
                            default: text_char = " ";
                        endcase
                    end

                    default: begin
                        case (pos)
                            0: text_char = "a";
                            1: text_char = "c";
                            2: text_char = "t";
                            3: text_char = ":";
                            4: text_char = cart_mode_char(cart_mode, 4'd0);
                            5: text_char = cart_mode_char(cart_mode, 4'd1);
                            6: text_char = cart_mode_char(cart_mode, 4'd2);
                            7: text_char = cart_mode_char(cart_mode, 4'd3);
                            8: text_char = cart_mode_char(cart_mode, 4'd4);
                            9: text_char = cart_mode_char(cart_mode, 4'd5);
                            10: text_char = cart_mode_char(cart_mode, 4'd6);
                            11: text_char = cart_mode_char(cart_mode, 4'd7);
                            12: text_char = cart_mode_char(cart_mode, 4'd8);
                            13: text_char = cart_mode_char(cart_mode, 4'd9);
                            14: text_char = cart_mode_char(cart_mode, 4'd10);
                            15: text_char = cart_mode_char(cart_mode, 4'd11);
                            default: text_char = " ";
                        endcase
                    end
                endcase
            end else if (view_mode == VIEW_CART_MENU) begin
                case (line)
                    2'd0: begin
                        case (pos)
                            0: text_char = "c";
                            1: text_char = "a";
                            2: text_char = "r";
                            3: text_char = "t";
                            4: text_char = "r";
                            5: text_char = "i";
                            6: text_char = "d";
                            7: text_char = "g";
                            8: text_char = "e";
                            default: text_char = " ";
                        endcase
                    end
                    2'd1: begin
                        case (pos)
                            0: text_char = (cart_selected == CART_DIAG) ? ">" : " ";
                            1: text_char = "1";
                            2: text_char = ".";
                            3: text_char = "b";
                            4: text_char = "o";
                            5: text_char = "o";
                            6: text_char = "t";
                            7: text_char = "_";
                            8: text_char = "a";
                            9: text_char = "n";
                            10: text_char = "a";
                            11: text_char = "l";
                            12: text_char = "y";
                            13: text_char = "z";
                            14: text_char = "e";
                            15: text_char = "r";
                            default: text_char = " ";
                        endcase
                    end
                    2'd2: begin
                        case (pos)
                            0: text_char = (cart_selected == CART_BEEP) ? ">" : " ";
                            1: text_char = "2";
                            2: text_char = ".";
                            3: text_char = "b";
                            4: text_char = "e";
                            5: text_char = "e";
                            6: text_char = "p";
                            15: text_char = (cart_mode == CART_BEEP) ? "*" : " ";
                            default: text_char = " ";
                        endcase
                    end
                    default: begin
                        case (pos)
                            0: text_char = (cart_selected == CART_ROMTEST) ? ">" : " ";
                            1: text_char = "3";
                            2: text_char = ".";
                            3: text_char = "d";
                            4: text_char = "i";
                            5: text_char = "a";
                            6: text_char = "g";
                            7: text_char = "_";
                            8: text_char = "c";
                            9: text_char = "a";
                            10: text_char = "r";
                            11: text_char = "t";
                            15: text_char = (cart_mode == CART_ROMTEST) ? "*" : " ";
                            default: text_char = " ";
                        endcase
                    end
                endcase
            end else if (view_mode == VIEW_DEBUG_MENU) begin
                case (line)
                    2'd0: begin
                        case (pos)
                            0: text_char = "c";
                            1: text_char = "a";
                            2: text_char = "r";
                            3: text_char = "t";
                            4: text_char = "-";
                            5: text_char = "d";
                            6: text_char = "e";
                            7: text_char = "b";
                            8: text_char = "u";
                            9: text_char = "g";
                            default: text_char = " ";
                        endcase
                    end
                    2'd1: begin
                        case (pos)
                            0: text_char = (debug_selected == 1'b0) ? ">" : " ";
                            1: text_char = "1";
                            2: text_char = ".";
                            3: text_char = "d";
                            4: text_char = "r";
                            5: text_char = "i";
                            6: text_char = "v";
                            7: text_char = "e";
                            default: text_char = " ";
                        endcase
                    end
                    2'd2: begin
                        case (pos)
                            0: text_char = (debug_selected == 1'b1) ? ">" : " ";
                            1: text_char = "2";
                            2: text_char = ".";
                            3: text_char = "r";
                            4: text_char = "e";
                            5: text_char = "a";
                            6: text_char = "d";
                            default: text_char = " ";
                        endcase
                    end
                    default: begin
                        case (pos)
                            0: text_char = "a";
                            1: text_char = "c";
                            2: text_char = "t";
                            3: text_char = ":";
                            4: text_char = cart_mode_char(cart_mode, 4'd0);
                            5: text_char = cart_mode_char(cart_mode, 4'd1);
                            6: text_char = cart_mode_char(cart_mode, 4'd2);
                            7: text_char = cart_mode_char(cart_mode, 4'd3);
                            8: text_char = cart_mode_char(cart_mode, 4'd4);
                            9: text_char = cart_mode_char(cart_mode, 4'd5);
                            10: text_char = cart_mode_char(cart_mode, 4'd6);
                            11: text_char = cart_mode_char(cart_mode, 4'd7);
                            12: text_char = cart_mode_char(cart_mode, 4'd8);
                            13: text_char = cart_mode_char(cart_mode, 4'd9);
                            14: text_char = cart_mode_char(cart_mode, 4'd10);
                            15: text_char = cart_mode_char(cart_mode, 4'd11);
                            default: text_char = " ";
                        endcase
                    end
                endcase
            end else if (view_mode == VIEW_DRIVE) begin
                case (line)
                    2'd0: begin
                        case (pos)
                            0: text_char = "w";
                            1: text_char = "r";
                            2: text_char = "i";
                            3: text_char = "t";
                            4: text_char = "e";
                            6: text_char = "t";
                            7: text_char = "e";
                            8: text_char = "s";
                            9: text_char = "t";
                            default: text_char = " ";
                        endcase
                    end

                    2'd1: begin
                        case (pos)
                            0: text_char = "D";
                            1: text_char = (drive_index >= 5'd10) ? "1" : "0";
                            2: text_char = dec_char((drive_index >= 5'd10) ? (drive_index - 5'd10) : drive_index[3:0]);
                            default: text_char = " ";
                        endcase
                    end

                    2'd2: begin
                        case (pos)
                            0: text_char = "o";
                            1: text_char = "u";
                            2: text_char = "t";
                            3: text_char = ":";
                            5: text_char = drive_level ? "H" : "L";
                            6: text_char = drive_level ? "I" : "O";
                            7: text_char = drive_level ? "G" : "W";
                            8: text_char = drive_level ? "H" : " ";
                            default: text_char = " ";
                        endcase
                    end

                    default: begin
                        case (pos)
                            0: text_char = "G";
                            1: text_char = "P";
                            2: text_char = "1";
                            3: text_char = "9";
                            4: text_char = "(";
                            5: text_char = "r";
                            6: text_char = ")";
                            8: text_char = test_io_in ? "H" : "L";
                            9: text_char = test_io_in ? "I" : "O";
                            10: text_char = test_io_in ? "G" : "W";
                            11: text_char = test_io_in ? "H" : " ";
                            default: text_char = " ";
                        endcase
                    end
                endcase
            end else if (view_mode == VIEW_READ) begin
                case (line)
                    2'd0: begin
                        case (pos)
                            0: text_char = "r";
                            1: text_char = "e";
                            2: text_char = "a";
                            3: text_char = "d";
                            5: text_char = "p";
                            6: text_char = "i";
                            7: text_char = "n";
                            default: text_char = " ";
                        endcase
                    end

                    2'd1: begin
                        case (pos)
                            0: text_char = read_name_char(read_index, 4'd0);
                            1: text_char = read_name_char(read_index, 4'd1);
                            2: text_char = read_name_char(read_index, 4'd2);
                            3: text_char = read_name_char(read_index, 4'd3);
                            default: text_char = " ";
                        endcase
                    end

                    2'd2: begin
                        case (pos)
                            0: text_char = "l";
                            1: text_char = "e";
                            2: text_char = "v";
                            3: text_char = "e";
                            4: text_char = "l";
                            5: text_char = ":";
                            7: text_char = read_value ? "H" : "L";
                            8: text_char = read_value ? "I" : "O";
                            9: text_char = read_value ? "G" : "W";
                            10: text_char = read_value ? "H" : " ";
                            default: text_char = " ";
                        endcase
                    end

                    default: begin
                        case (pos)
                            0: text_char = "G";
                            1: text_char = "P";
                            2: text_char = "1";
                            3: text_char = "9";
                            4: text_char = "(";
                            5: text_char = "r";
                            6: text_char = ")";
                            8: text_char = "1";
                            9: text_char = "h";
                            10: text_char = "z";
                            default: text_char = " ";
                        endcase
                    end
                endcase
            end else begin
                case (line)
                    2'd0: begin
                        case (pos)
                            0: text_char = "d";
                            1: text_char = "i";
                            2: text_char = "a";
                            3: text_char = "g";
                            5: text_char = "$";
                            6: text_char = addr_char(current_addr, 2'd0);
                            7: text_char = addr_char(current_addr, 2'd1);
                            8: text_char = addr_char(current_addr, 2'd2);
                            9: text_char = addr_char(current_addr, 2'd3);
                            default: text_char = " ";
                        endcase
                    end
                    2'd1: begin
                        case (pos)
                            0: text_char = "M";
                            1: text_char = ":";
                            2: text_char = boot_magic_ok ? GLYPH_CHECK : "X";
                            5: text_char = "C";
                            6: text_char = ":";
                            7: text_char = boot_code_ok ? GLYPH_CHECK : "X";
                            10: text_char = "I";
                            11: text_char = ":";
                            12: text_char = boot_idle_ok ? GLYPH_CHECK : "X";
                            default: text_char = " ";
                        endcase
                    end
                    2'd2: begin
                        case (pos)
                            0: text_char = "1";
                            1: text_char = ":";
                            2: text_char = addr_char(trace_addr0, 2'd0);
                            3: text_char = addr_char(trace_addr0, 2'd1);
                            4: text_char = addr_char(trace_addr0, 2'd2);
                            5: text_char = addr_char(trace_addr0, 2'd3);
                            8: text_char = "2";
                            9: text_char = ":";
                            10: text_char = addr_char(trace_addr1, 2'd0);
                            11: text_char = addr_char(trace_addr1, 2'd1);
                            12: text_char = addr_char(trace_addr1, 2'd2);
                            13: text_char = addr_char(trace_addr1, 2'd3);
                            default: text_char = " ";
                        endcase
                    end
                    2'd3: begin
                        case (pos)
                            0: text_char = "3";
                            1: text_char = ":";
                            2: text_char = addr_char(trace_addr2, 2'd0);
                            3: text_char = addr_char(trace_addr2, 2'd1);
                            4: text_char = addr_char(trace_addr2, 2'd2);
                            5: text_char = addr_char(trace_addr2, 2'd3);
                            8: text_char = "4";
                            9: text_char = ":";
                            10: text_char = addr_char(trace_addr3, 2'd0);
                            11: text_char = addr_char(trace_addr3, 2'd1);
                            12: text_char = addr_char(trace_addr3, 2'd2);
                            13: text_char = addr_char(trace_addr3, 2'd3);
                            default: text_char = " ";
                        endcase
                    end
                endcase
            end
        end
    endfunction

    function [7:0] font_rom;
        input [10:0] addr;
        begin
            case (addr)
                11'd0: font_rom = 8'h00;
                11'd1: font_rom = 8'h00;
                11'd2: font_rom = 8'h00;
                11'd3: font_rom = 8'h00;
                11'd4: font_rom = 8'h00;
                11'd5: font_rom = 8'h00;
                11'd6: font_rom = 8'h00;
                11'd7: font_rom = 8'h00;
                11'd8: font_rom = 8'h18;
                11'd9: font_rom = 8'h3C;
                11'd10: font_rom = 8'h3C;
                11'd11: font_rom = 8'h18;
                11'd12: font_rom = 8'h18;
                11'd13: font_rom = 8'h00;
                11'd14: font_rom = 8'h18;
                11'd15: font_rom = 8'h00;
                11'd16: font_rom = 8'h6C;
                11'd17: font_rom = 8'h6C;
                11'd18: font_rom = 8'h24;
                11'd19: font_rom = 8'h00;
                11'd20: font_rom = 8'h00;
                11'd21: font_rom = 8'h00;
                11'd22: font_rom = 8'h00;
                11'd23: font_rom = 8'h00;
                11'd24: font_rom = 8'h6C;
                11'd25: font_rom = 8'h6C;
                11'd26: font_rom = 8'hFE;
                11'd27: font_rom = 8'h6C;
                11'd28: font_rom = 8'hFE;
                11'd29: font_rom = 8'h6C;
                11'd30: font_rom = 8'h6C;
                11'd31: font_rom = 8'h00;
                11'd32: font_rom = 8'h18;
                11'd33: font_rom = 8'h3E;
                11'd34: font_rom = 8'h60;
                11'd35: font_rom = 8'h3C;
                11'd36: font_rom = 8'h06;
                11'd37: font_rom = 8'h7C;
                11'd38: font_rom = 8'h18;
                11'd39: font_rom = 8'h00;
                11'd40: font_rom = 8'h00;
                11'd41: font_rom = 8'hC6;
                11'd42: font_rom = 8'hCC;
                11'd43: font_rom = 8'h18;
                11'd44: font_rom = 8'h30;
                11'd45: font_rom = 8'h66;
                11'd46: font_rom = 8'hC6;
                11'd47: font_rom = 8'h00;
                11'd48: font_rom = 8'h38;
                11'd49: font_rom = 8'h6C;
                11'd50: font_rom = 8'h38;
                11'd51: font_rom = 8'h76;
                11'd52: font_rom = 8'hDC;
                11'd53: font_rom = 8'hCC;
                11'd54: font_rom = 8'h76;
                11'd55: font_rom = 8'h00;
                11'd56: font_rom = 8'h30;
                11'd57: font_rom = 8'h30;
                11'd58: font_rom = 8'h60;
                11'd59: font_rom = 8'h00;
                11'd60: font_rom = 8'h00;
                11'd61: font_rom = 8'h00;
                11'd62: font_rom = 8'h00;
                11'd63: font_rom = 8'h00;
                11'd64: font_rom = 8'h0C;
                11'd65: font_rom = 8'h18;
                11'd66: font_rom = 8'h30;
                11'd67: font_rom = 8'h30;
                11'd68: font_rom = 8'h30;
                11'd69: font_rom = 8'h18;
                11'd70: font_rom = 8'h0C;
                11'd71: font_rom = 8'h00;
                11'd72: font_rom = 8'h30;
                11'd73: font_rom = 8'h18;
                11'd74: font_rom = 8'h0C;
                11'd75: font_rom = 8'h0C;
                11'd76: font_rom = 8'h0C;
                11'd77: font_rom = 8'h18;
                11'd78: font_rom = 8'h30;
                11'd79: font_rom = 8'h00;
                11'd80: font_rom = 8'h00;
                11'd81: font_rom = 8'h66;
                11'd82: font_rom = 8'h3C;
                11'd83: font_rom = 8'hFF;
                11'd84: font_rom = 8'h3C;
                11'd85: font_rom = 8'h66;
                11'd86: font_rom = 8'h00;
                11'd87: font_rom = 8'h00;
                11'd88: font_rom = 8'h00;
                11'd89: font_rom = 8'h18;
                11'd90: font_rom = 8'h18;
                11'd91: font_rom = 8'h7E;
                11'd92: font_rom = 8'h18;
                11'd93: font_rom = 8'h18;
                11'd94: font_rom = 8'h00;
                11'd95: font_rom = 8'h00;
                11'd96: font_rom = 8'h00;
                11'd97: font_rom = 8'h00;
                11'd98: font_rom = 8'h00;
                11'd99: font_rom = 8'h00;
                11'd100: font_rom = 8'h00;
                11'd101: font_rom = 8'h18;
                11'd102: font_rom = 8'h18;
                11'd103: font_rom = 8'h30;
                11'd104: font_rom = 8'h00;
                11'd105: font_rom = 8'h00;
                11'd106: font_rom = 8'h00;
                11'd107: font_rom = 8'h7E;
                11'd108: font_rom = 8'h00;
                11'd109: font_rom = 8'h00;
                11'd110: font_rom = 8'h00;
                11'd111: font_rom = 8'h00;
                11'd112: font_rom = 8'h00;
                11'd113: font_rom = 8'h00;
                11'd114: font_rom = 8'h00;
                11'd115: font_rom = 8'h00;
                11'd116: font_rom = 8'h00;
                11'd117: font_rom = 8'h18;
                11'd118: font_rom = 8'h18;
                11'd119: font_rom = 8'h00;
                11'd120: font_rom = 8'h06;
                11'd121: font_rom = 8'h0C;
                11'd122: font_rom = 8'h18;
                11'd123: font_rom = 8'h30;
                11'd124: font_rom = 8'h60;
                11'd125: font_rom = 8'hC0;
                11'd126: font_rom = 8'h80;
                11'd127: font_rom = 8'h00;
                11'd128: font_rom = 8'h7C;
                11'd129: font_rom = 8'hC6;
                11'd130: font_rom = 8'hCE;
                11'd131: font_rom = 8'hDE;
                11'd132: font_rom = 8'hF6;
                11'd133: font_rom = 8'hE6;
                11'd134: font_rom = 8'h7C;
                11'd135: font_rom = 8'h00;
                11'd136: font_rom = 8'h18;
                11'd137: font_rom = 8'h38;
                11'd138: font_rom = 8'h18;
                11'd139: font_rom = 8'h18;
                11'd140: font_rom = 8'h18;
                11'd141: font_rom = 8'h18;
                11'd142: font_rom = 8'h7E;
                11'd143: font_rom = 8'h00;
                11'd144: font_rom = 8'h7C;
                11'd145: font_rom = 8'hC6;
                11'd146: font_rom = 8'h06;
                11'd147: font_rom = 8'h1C;
                11'd148: font_rom = 8'h30;
                11'd149: font_rom = 8'h66;
                11'd150: font_rom = 8'hFE;
                11'd151: font_rom = 8'h00;
                11'd152: font_rom = 8'h7C;
                11'd153: font_rom = 8'hC6;
                11'd154: font_rom = 8'h06;
                11'd155: font_rom = 8'h3C;
                11'd156: font_rom = 8'h06;
                11'd157: font_rom = 8'hC6;
                11'd158: font_rom = 8'h7C;
                11'd159: font_rom = 8'h00;
                11'd160: font_rom = 8'h1C;
                11'd161: font_rom = 8'h3C;
                11'd162: font_rom = 8'h6C;
                11'd163: font_rom = 8'hCC;
                11'd164: font_rom = 8'hFE;
                11'd165: font_rom = 8'h0C;
                11'd166: font_rom = 8'h1E;
                11'd167: font_rom = 8'h00;
                11'd168: font_rom = 8'hFE;
                11'd169: font_rom = 8'hC0;
                11'd170: font_rom = 8'hFC;
                11'd171: font_rom = 8'h06;
                11'd172: font_rom = 8'h06;
                11'd173: font_rom = 8'hC6;
                11'd174: font_rom = 8'h7C;
                11'd175: font_rom = 8'h00;
                11'd176: font_rom = 8'h38;
                11'd177: font_rom = 8'h60;
                11'd178: font_rom = 8'hC0;
                11'd179: font_rom = 8'hFC;
                11'd180: font_rom = 8'hC6;
                11'd181: font_rom = 8'hC6;
                11'd182: font_rom = 8'h7C;
                11'd183: font_rom = 8'h00;
                11'd184: font_rom = 8'hFE;
                11'd185: font_rom = 8'hC6;
                11'd186: font_rom = 8'h0C;
                11'd187: font_rom = 8'h18;
                11'd188: font_rom = 8'h30;
                11'd189: font_rom = 8'h30;
                11'd190: font_rom = 8'h30;
                11'd191: font_rom = 8'h00;
                11'd192: font_rom = 8'h7C;
                11'd193: font_rom = 8'hC6;
                11'd194: font_rom = 8'hC6;
                11'd195: font_rom = 8'h7C;
                11'd196: font_rom = 8'hC6;
                11'd197: font_rom = 8'hC6;
                11'd198: font_rom = 8'h7C;
                11'd199: font_rom = 8'h00;
                11'd200: font_rom = 8'h7C;
                11'd201: font_rom = 8'hC6;
                11'd202: font_rom = 8'hC6;
                11'd203: font_rom = 8'h7E;
                11'd204: font_rom = 8'h06;
                11'd205: font_rom = 8'h0C;
                11'd206: font_rom = 8'h78;
                11'd207: font_rom = 8'h00;
                11'd208: font_rom = 8'h00;
                11'd209: font_rom = 8'h18;
                11'd210: font_rom = 8'h18;
                11'd211: font_rom = 8'h00;
                11'd212: font_rom = 8'h00;
                11'd213: font_rom = 8'h18;
                11'd214: font_rom = 8'h18;
                11'd215: font_rom = 8'h00;
                11'd216: font_rom = 8'h00;
                11'd217: font_rom = 8'h18;
                11'd218: font_rom = 8'h18;
                11'd219: font_rom = 8'h00;
                11'd220: font_rom = 8'h00;
                11'd221: font_rom = 8'h18;
                11'd222: font_rom = 8'h18;
                11'd223: font_rom = 8'h30;
                11'd224: font_rom = 8'h0E;
                11'd225: font_rom = 8'h18;
                11'd226: font_rom = 8'h30;
                11'd227: font_rom = 8'h60;
                11'd228: font_rom = 8'h30;
                11'd229: font_rom = 8'h18;
                11'd230: font_rom = 8'h0E;
                11'd231: font_rom = 8'h00;
                11'd232: font_rom = 8'h00;
                11'd233: font_rom = 8'h00;
                11'd234: font_rom = 8'h7E;
                11'd235: font_rom = 8'h00;
                11'd236: font_rom = 8'h7E;
                11'd237: font_rom = 8'h00;
                11'd238: font_rom = 8'h00;
                11'd239: font_rom = 8'h00;
                11'd240: font_rom = 8'h70;
                11'd241: font_rom = 8'h18;
                11'd242: font_rom = 8'h0C;
                11'd243: font_rom = 8'h06;
                11'd244: font_rom = 8'h0C;
                11'd245: font_rom = 8'h18;
                11'd246: font_rom = 8'h70;
                11'd247: font_rom = 8'h00;
                11'd248: font_rom = 8'h7C;
                11'd249: font_rom = 8'hC6;
                11'd250: font_rom = 8'h0C;
                11'd251: font_rom = 8'h18;
                11'd252: font_rom = 8'h18;
                11'd253: font_rom = 8'h00;
                11'd254: font_rom = 8'h18;
                11'd255: font_rom = 8'h00;
                11'd256: font_rom = 8'h7C;
                11'd257: font_rom = 8'hC6;
                11'd258: font_rom = 8'hDE;
                11'd259: font_rom = 8'hDE;
                11'd260: font_rom = 8'hDE;
                11'd261: font_rom = 8'hC0;
                11'd262: font_rom = 8'h78;
                11'd263: font_rom = 8'h00;
                11'd264: font_rom = 8'h38;
                11'd265: font_rom = 8'h6C;
                11'd266: font_rom = 8'hC6;
                11'd267: font_rom = 8'hC6;
                11'd268: font_rom = 8'hFE;
                11'd269: font_rom = 8'hC6;
                11'd270: font_rom = 8'hC6;
                11'd271: font_rom = 8'h00;
                11'd272: font_rom = 8'hFC;
                11'd273: font_rom = 8'h66;
                11'd274: font_rom = 8'h66;
                11'd275: font_rom = 8'h7C;
                11'd276: font_rom = 8'h66;
                11'd277: font_rom = 8'h66;
                11'd278: font_rom = 8'hFC;
                11'd279: font_rom = 8'h00;
                11'd280: font_rom = 8'h3C;
                11'd281: font_rom = 8'h66;
                11'd282: font_rom = 8'hC0;
                11'd283: font_rom = 8'hC0;
                11'd284: font_rom = 8'hC0;
                11'd285: font_rom = 8'h66;
                11'd286: font_rom = 8'h3C;
                11'd287: font_rom = 8'h00;
                11'd288: font_rom = 8'hF8;
                11'd289: font_rom = 8'h6C;
                11'd290: font_rom = 8'h66;
                11'd291: font_rom = 8'h66;
                11'd292: font_rom = 8'h66;
                11'd293: font_rom = 8'h6C;
                11'd294: font_rom = 8'hF8;
                11'd295: font_rom = 8'h00;
                11'd296: font_rom = 8'hFE;
                11'd297: font_rom = 8'h62;
                11'd298: font_rom = 8'h68;
                11'd299: font_rom = 8'h78;
                11'd300: font_rom = 8'h68;
                11'd301: font_rom = 8'h62;
                11'd302: font_rom = 8'hFE;
                11'd303: font_rom = 8'h00;
                11'd304: font_rom = 8'hFE;
                11'd305: font_rom = 8'h62;
                11'd306: font_rom = 8'h68;
                11'd307: font_rom = 8'h78;
                11'd308: font_rom = 8'h68;
                11'd309: font_rom = 8'h60;
                11'd310: font_rom = 8'hF0;
                11'd311: font_rom = 8'h00;
                11'd312: font_rom = 8'h3C;
                11'd313: font_rom = 8'h66;
                11'd314: font_rom = 8'hC0;
                11'd315: font_rom = 8'hC0;
                11'd316: font_rom = 8'hCE;
                11'd317: font_rom = 8'h66;
                11'd318: font_rom = 8'h3E;
                11'd319: font_rom = 8'h00;
                11'd320: font_rom = 8'hC6;
                11'd321: font_rom = 8'hC6;
                11'd322: font_rom = 8'hC6;
                11'd323: font_rom = 8'hFE;
                11'd324: font_rom = 8'hC6;
                11'd325: font_rom = 8'hC6;
                11'd326: font_rom = 8'hC6;
                11'd327: font_rom = 8'h00;
                11'd328: font_rom = 8'h3C;
                11'd329: font_rom = 8'h18;
                11'd330: font_rom = 8'h18;
                11'd331: font_rom = 8'h18;
                11'd332: font_rom = 8'h18;
                11'd333: font_rom = 8'h18;
                11'd334: font_rom = 8'h3C;
                11'd335: font_rom = 8'h00;
                11'd336: font_rom = 8'h1E;
                11'd337: font_rom = 8'h0C;
                11'd338: font_rom = 8'h0C;
                11'd339: font_rom = 8'h0C;
                11'd340: font_rom = 8'hCC;
                11'd341: font_rom = 8'hCC;
                11'd342: font_rom = 8'h78;
                11'd343: font_rom = 8'h00;
                11'd344: font_rom = 8'hE6;
                11'd345: font_rom = 8'h66;
                11'd346: font_rom = 8'h6C;
                11'd347: font_rom = 8'h78;
                11'd348: font_rom = 8'h6C;
                11'd349: font_rom = 8'h66;
                11'd350: font_rom = 8'hE6;
                11'd351: font_rom = 8'h00;
                11'd352: font_rom = 8'hF0;
                11'd353: font_rom = 8'h60;
                11'd354: font_rom = 8'h60;
                11'd355: font_rom = 8'h60;
                11'd356: font_rom = 8'h62;
                11'd357: font_rom = 8'h66;
                11'd358: font_rom = 8'hFE;
                11'd359: font_rom = 8'h00;
                11'd360: font_rom = 8'hC6;
                11'd361: font_rom = 8'hEE;
                11'd362: font_rom = 8'hFE;
                11'd363: font_rom = 8'hFE;
                11'd364: font_rom = 8'hD6;
                11'd365: font_rom = 8'hC6;
                11'd366: font_rom = 8'hC6;
                11'd367: font_rom = 8'h00;
                11'd368: font_rom = 8'hC6;
                11'd369: font_rom = 8'hE6;
                11'd370: font_rom = 8'hF6;
                11'd371: font_rom = 8'hDE;
                11'd372: font_rom = 8'hCE;
                11'd373: font_rom = 8'hC6;
                11'd374: font_rom = 8'hC6;
                11'd375: font_rom = 8'h00;
                11'd376: font_rom = 8'h7C;
                11'd377: font_rom = 8'hC6;
                11'd378: font_rom = 8'hC6;
                11'd379: font_rom = 8'hC6;
                11'd380: font_rom = 8'hC6;
                11'd381: font_rom = 8'hC6;
                11'd382: font_rom = 8'h7C;
                11'd383: font_rom = 8'h00;
                11'd384: font_rom = 8'hFC;
                11'd385: font_rom = 8'h66;
                11'd386: font_rom = 8'h66;
                11'd387: font_rom = 8'h7C;
                11'd388: font_rom = 8'h60;
                11'd389: font_rom = 8'h60;
                11'd390: font_rom = 8'hF0;
                11'd391: font_rom = 8'h00;
                11'd392: font_rom = 8'h7C;
                11'd393: font_rom = 8'hC6;
                11'd394: font_rom = 8'hC6;
                11'd395: font_rom = 8'hC6;
                11'd396: font_rom = 8'hD6;
                11'd397: font_rom = 8'hCC;
                11'd398: font_rom = 8'h76;
                11'd399: font_rom = 8'h00;
                11'd400: font_rom = 8'hFC;
                11'd401: font_rom = 8'h66;
                11'd402: font_rom = 8'h66;
                11'd403: font_rom = 8'h7C;
                11'd404: font_rom = 8'h6C;
                11'd405: font_rom = 8'h66;
                11'd406: font_rom = 8'hE6;
                11'd407: font_rom = 8'h00;
                11'd408: font_rom = 8'h7C;
                11'd409: font_rom = 8'hC6;
                11'd410: font_rom = 8'hE0;
                11'd411: font_rom = 8'h78;
                11'd412: font_rom = 8'h0E;
                11'd413: font_rom = 8'hC6;
                11'd414: font_rom = 8'h7C;
                11'd415: font_rom = 8'h00;
                11'd416: font_rom = 8'h7E;
                11'd417: font_rom = 8'h7E;
                11'd418: font_rom = 8'h5A;
                11'd419: font_rom = 8'h18;
                11'd420: font_rom = 8'h18;
                11'd421: font_rom = 8'h18;
                11'd422: font_rom = 8'h3C;
                11'd423: font_rom = 8'h00;
                11'd424: font_rom = 8'hC6;
                11'd425: font_rom = 8'hC6;
                11'd426: font_rom = 8'hC6;
                11'd427: font_rom = 8'hC6;
                11'd428: font_rom = 8'hC6;
                11'd429: font_rom = 8'hC6;
                11'd430: font_rom = 8'h7C;
                11'd431: font_rom = 8'h00;
                11'd432: font_rom = 8'hC6;
                11'd433: font_rom = 8'hC6;
                11'd434: font_rom = 8'hC6;
                11'd435: font_rom = 8'hC6;
                11'd436: font_rom = 8'hC6;
                11'd437: font_rom = 8'h6C;
                11'd438: font_rom = 8'h38;
                11'd439: font_rom = 8'h00;
                11'd440: font_rom = 8'hC6;
                11'd441: font_rom = 8'hC6;
                11'd442: font_rom = 8'hC6;
                11'd443: font_rom = 8'hD6;
                11'd444: font_rom = 8'hFE;
                11'd445: font_rom = 8'hEE;
                11'd446: font_rom = 8'hC6;
                11'd447: font_rom = 8'h00;
                11'd448: font_rom = 8'hC6;
                11'd449: font_rom = 8'hC6;
                11'd450: font_rom = 8'h6C;
                11'd451: font_rom = 8'h38;
                11'd452: font_rom = 8'h38;
                11'd453: font_rom = 8'h6C;
                11'd454: font_rom = 8'hC6;
                11'd455: font_rom = 8'h00;
                11'd456: font_rom = 8'h66;
                11'd457: font_rom = 8'h66;
                11'd458: font_rom = 8'h66;
                11'd459: font_rom = 8'h3C;
                11'd460: font_rom = 8'h18;
                11'd461: font_rom = 8'h18;
                11'd462: font_rom = 8'h3C;
                11'd463: font_rom = 8'h00;
                11'd464: font_rom = 8'hFE;
                11'd465: font_rom = 8'hC6;
                11'd466: font_rom = 8'h8C;
                11'd467: font_rom = 8'h18;
                11'd468: font_rom = 8'h32;
                11'd469: font_rom = 8'h66;
                11'd470: font_rom = 8'hFE;
                11'd471: font_rom = 8'h00;
                11'd472: font_rom = 8'h3C;
                11'd473: font_rom = 8'h30;
                11'd474: font_rom = 8'h30;
                11'd475: font_rom = 8'h30;
                11'd476: font_rom = 8'h30;
                11'd477: font_rom = 8'h30;
                11'd478: font_rom = 8'h3C;
                11'd479: font_rom = 8'h00;
                11'd480: font_rom = 8'hC0;
                11'd481: font_rom = 8'h60;
                11'd482: font_rom = 8'h30;
                11'd483: font_rom = 8'h18;
                11'd484: font_rom = 8'h0C;
                11'd485: font_rom = 8'h06;
                11'd486: font_rom = 8'h02;
                11'd487: font_rom = 8'h00;
                11'd488: font_rom = 8'h3C;
                11'd489: font_rom = 8'h0C;
                11'd490: font_rom = 8'h0C;
                11'd491: font_rom = 8'h0C;
                11'd492: font_rom = 8'h0C;
                11'd493: font_rom = 8'h0C;
                11'd494: font_rom = 8'h3C;
                11'd495: font_rom = 8'h00;
                11'd496: font_rom = 8'h10;
                11'd497: font_rom = 8'h38;
                11'd498: font_rom = 8'h6C;
                11'd499: font_rom = 8'hC6;
                11'd500: font_rom = 8'h00;
                11'd501: font_rom = 8'h00;
                11'd502: font_rom = 8'h00;
                11'd503: font_rom = 8'h00;
                11'd504: font_rom = 8'h00;
                11'd505: font_rom = 8'h00;
                11'd506: font_rom = 8'h00;
                11'd507: font_rom = 8'h00;
                11'd508: font_rom = 8'h00;
                11'd509: font_rom = 8'h00;
                11'd510: font_rom = 8'h00;
                11'd511: font_rom = 8'hFF;
                11'd512: font_rom = 8'h30;
                11'd513: font_rom = 8'h18;
                11'd514: font_rom = 8'h0C;
                11'd515: font_rom = 8'h00;
                11'd516: font_rom = 8'h00;
                11'd517: font_rom = 8'h00;
                11'd518: font_rom = 8'h00;
                11'd519: font_rom = 8'h00;
                11'd520: font_rom = 8'h00;
                11'd521: font_rom = 8'h00;
                11'd522: font_rom = 8'h78;
                11'd523: font_rom = 8'h0C;
                11'd524: font_rom = 8'h7C;
                11'd525: font_rom = 8'hCC;
                11'd526: font_rom = 8'h76;
                11'd527: font_rom = 8'h00;
                11'd528: font_rom = 8'hE0;
                11'd529: font_rom = 8'h60;
                11'd530: font_rom = 8'h60;
                11'd531: font_rom = 8'h7C;
                11'd532: font_rom = 8'h66;
                11'd533: font_rom = 8'h66;
                11'd534: font_rom = 8'hDC;
                11'd535: font_rom = 8'h00;
                11'd536: font_rom = 8'h00;
                11'd537: font_rom = 8'h00;
                11'd538: font_rom = 8'h7C;
                11'd539: font_rom = 8'hC6;
                11'd540: font_rom = 8'hC0;
                11'd541: font_rom = 8'hC6;
                11'd542: font_rom = 8'h7C;
                11'd543: font_rom = 8'h00;
                11'd544: font_rom = 8'h1C;
                11'd545: font_rom = 8'h0C;
                11'd546: font_rom = 8'h0C;
                11'd547: font_rom = 8'h7C;
                11'd548: font_rom = 8'hCC;
                11'd549: font_rom = 8'hCC;
                11'd550: font_rom = 8'h76;
                11'd551: font_rom = 8'h00;
                11'd552: font_rom = 8'h00;
                11'd553: font_rom = 8'h00;
                11'd554: font_rom = 8'h7C;
                11'd555: font_rom = 8'hC6;
                11'd556: font_rom = 8'hFE;
                11'd557: font_rom = 8'hC0;
                11'd558: font_rom = 8'h7C;
                11'd559: font_rom = 8'h00;
                11'd560: font_rom = 8'h38;
                11'd561: font_rom = 8'h6C;
                11'd562: font_rom = 8'h60;
                11'd563: font_rom = 8'hF0;
                11'd564: font_rom = 8'h60;
                11'd565: font_rom = 8'h60;
                11'd566: font_rom = 8'hF0;
                11'd567: font_rom = 8'h00;
                11'd568: font_rom = 8'h00;
                11'd569: font_rom = 8'h00;
                11'd570: font_rom = 8'h76;
                11'd571: font_rom = 8'hCC;
                11'd572: font_rom = 8'hCC;
                11'd573: font_rom = 8'h7C;
                11'd574: font_rom = 8'h0C;
                11'd575: font_rom = 8'hF8;
                11'd576: font_rom = 8'hE0;
                11'd577: font_rom = 8'h60;
                11'd578: font_rom = 8'h6C;
                11'd579: font_rom = 8'h76;
                11'd580: font_rom = 8'h66;
                11'd581: font_rom = 8'h66;
                11'd582: font_rom = 8'hE6;
                11'd583: font_rom = 8'h00;
                11'd584: font_rom = 8'h18;
                11'd585: font_rom = 8'h00;
                11'd586: font_rom = 8'h38;
                11'd587: font_rom = 8'h18;
                11'd588: font_rom = 8'h18;
                11'd589: font_rom = 8'h18;
                11'd590: font_rom = 8'h3C;
                11'd591: font_rom = 8'h00;
                11'd592: font_rom = 8'h06;
                11'd593: font_rom = 8'h00;
                11'd594: font_rom = 8'h06;
                11'd595: font_rom = 8'h06;
                11'd596: font_rom = 8'h06;
                11'd597: font_rom = 8'h66;
                11'd598: font_rom = 8'h66;
                11'd599: font_rom = 8'h3C;
                11'd600: font_rom = 8'hE0;
                11'd601: font_rom = 8'h60;
                11'd602: font_rom = 8'h66;
                11'd603: font_rom = 8'h6C;
                11'd604: font_rom = 8'h78;
                11'd605: font_rom = 8'h6C;
                11'd606: font_rom = 8'hE6;
                11'd607: font_rom = 8'h00;
                11'd608: font_rom = 8'h38;
                11'd609: font_rom = 8'h18;
                11'd610: font_rom = 8'h18;
                11'd611: font_rom = 8'h18;
                11'd612: font_rom = 8'h18;
                11'd613: font_rom = 8'h18;
                11'd614: font_rom = 8'h3C;
                11'd615: font_rom = 8'h00;
                11'd616: font_rom = 8'h00;
                11'd617: font_rom = 8'h00;
                11'd618: font_rom = 8'hCC;
                11'd619: font_rom = 8'hFE;
                11'd620: font_rom = 8'hFE;
                11'd621: font_rom = 8'hD6;
                11'd622: font_rom = 8'hC6;
                11'd623: font_rom = 8'h00;
                11'd624: font_rom = 8'h00;
                11'd625: font_rom = 8'h00;
                11'd626: font_rom = 8'hDC;
                11'd627: font_rom = 8'h66;
                11'd628: font_rom = 8'h66;
                11'd629: font_rom = 8'h66;
                11'd630: font_rom = 8'h66;
                11'd631: font_rom = 8'h00;
                11'd632: font_rom = 8'h00;
                11'd633: font_rom = 8'h00;
                11'd634: font_rom = 8'h7C;
                11'd635: font_rom = 8'hC6;
                11'd636: font_rom = 8'hC6;
                11'd637: font_rom = 8'hC6;
                11'd638: font_rom = 8'h7C;
                11'd639: font_rom = 8'h00;
                11'd640: font_rom = 8'h00;
                11'd641: font_rom = 8'h00;
                11'd642: font_rom = 8'hDC;
                11'd643: font_rom = 8'h66;
                11'd644: font_rom = 8'h66;
                11'd645: font_rom = 8'h7C;
                11'd646: font_rom = 8'h60;
                11'd647: font_rom = 8'hF0;
                11'd648: font_rom = 8'h00;
                11'd649: font_rom = 8'h00;
                11'd650: font_rom = 8'h76;
                11'd651: font_rom = 8'hCC;
                11'd652: font_rom = 8'hCC;
                11'd653: font_rom = 8'h7C;
                11'd654: font_rom = 8'h0C;
                11'd655: font_rom = 8'h1E;
                11'd656: font_rom = 8'h00;
                11'd657: font_rom = 8'h00;
                11'd658: font_rom = 8'hDC;
                11'd659: font_rom = 8'h76;
                11'd660: font_rom = 8'h66;
                11'd661: font_rom = 8'h60;
                11'd662: font_rom = 8'hF0;
                11'd663: font_rom = 8'h00;
                11'd664: font_rom = 8'h00;
                11'd665: font_rom = 8'h00;
                11'd666: font_rom = 8'h7E;
                11'd667: font_rom = 8'hC0;
                11'd668: font_rom = 8'h7C;
                11'd669: font_rom = 8'h06;
                11'd670: font_rom = 8'hFC;
                11'd671: font_rom = 8'h00;
                11'd672: font_rom = 8'h10;
                11'd673: font_rom = 8'h30;
                11'd674: font_rom = 8'h7C;
                11'd675: font_rom = 8'h30;
                11'd676: font_rom = 8'h30;
                11'd677: font_rom = 8'h34;
                11'd678: font_rom = 8'h18;
                11'd679: font_rom = 8'h00;
                11'd680: font_rom = 8'h00;
                11'd681: font_rom = 8'h00;
                11'd682: font_rom = 8'hCC;
                11'd683: font_rom = 8'hCC;
                11'd684: font_rom = 8'hCC;
                11'd685: font_rom = 8'hCC;
                11'd686: font_rom = 8'h76;
                11'd687: font_rom = 8'h00;
                11'd688: font_rom = 8'h00;
                11'd689: font_rom = 8'h00;
                11'd690: font_rom = 8'hC6;
                11'd691: font_rom = 8'hC6;
                11'd692: font_rom = 8'hC6;
                11'd693: font_rom = 8'h6C;
                11'd694: font_rom = 8'h38;
                11'd695: font_rom = 8'h00;
                11'd696: font_rom = 8'h00;
                11'd697: font_rom = 8'h00;
                11'd698: font_rom = 8'hC6;
                11'd699: font_rom = 8'hD6;
                11'd700: font_rom = 8'hFE;
                11'd701: font_rom = 8'hFE;
                11'd702: font_rom = 8'h6C;
                11'd703: font_rom = 8'h00;
                11'd704: font_rom = 8'h00;
                11'd705: font_rom = 8'h00;
                11'd706: font_rom = 8'hC6;
                11'd707: font_rom = 8'h6C;
                11'd708: font_rom = 8'h38;
                11'd709: font_rom = 8'h6C;
                11'd710: font_rom = 8'hC6;
                11'd711: font_rom = 8'h00;
                11'd712: font_rom = 8'h00;
                11'd713: font_rom = 8'h00;
                11'd714: font_rom = 8'hC6;
                11'd715: font_rom = 8'hC6;
                11'd716: font_rom = 8'hC6;
                11'd717: font_rom = 8'h7E;
                11'd718: font_rom = 8'h06;
                11'd719: font_rom = 8'hFC;
                11'd720: font_rom = 8'h00;
                11'd721: font_rom = 8'h00;
                11'd722: font_rom = 8'hFE;
                11'd723: font_rom = 8'h98;
                11'd724: font_rom = 8'h30;
                11'd725: font_rom = 8'h64;
                11'd726: font_rom = 8'hFE;
                11'd727: font_rom = 8'h00;
                11'd728: font_rom = 8'h0E;
                11'd729: font_rom = 8'h18;
                11'd730: font_rom = 8'h18;
                11'd731: font_rom = 8'h70;
                11'd732: font_rom = 8'h18;
                11'd733: font_rom = 8'h18;
                11'd734: font_rom = 8'h0E;
                11'd735: font_rom = 8'h00;
                11'd736: font_rom = 8'h18;
                11'd737: font_rom = 8'h18;
                11'd738: font_rom = 8'h18;
                11'd739: font_rom = 8'h00;
                11'd740: font_rom = 8'h18;
                11'd741: font_rom = 8'h18;
                11'd742: font_rom = 8'h18;
                11'd743: font_rom = 8'h00;
                11'd744: font_rom = 8'h70;
                11'd745: font_rom = 8'h18;
                11'd746: font_rom = 8'h18;
                11'd747: font_rom = 8'h0E;
                11'd748: font_rom = 8'h18;
                11'd749: font_rom = 8'h18;
                11'd750: font_rom = 8'h70;
                11'd751: font_rom = 8'h00;
                11'd752: font_rom = 8'h00;
                11'd753: font_rom = 8'h01;
                11'd754: font_rom = 8'h03;
                11'd755: font_rom = 8'h86;
                11'd756: font_rom = 8'hCC;
                11'd757: font_rom = 8'h78;
                11'd758: font_rom = 8'h30;
                11'd759: font_rom = 8'h00;
                11'd1008: font_rom = 8'h00;
                11'd1009: font_rom = 8'h01;
                11'd1010: font_rom = 8'h03;
                11'd1011: font_rom = 8'h86;
                11'd1012: font_rom = 8'hCC;
                11'd1013: font_rom = 8'h78;
                11'd1014: font_rom = 8'h30;
                11'd1015: font_rom = 8'h00;
                default: font_rom = 8'h00;
            endcase
        end
    endfunction

    function [7:0] glyph_row;
        input [7:0] ch;
        input [2:0] row;
        reg [10:0] addr;
        begin
            if (ch < 8'd32 || ch > 8'd126) begin
                glyph_row = 8'h00;
            end else begin
                addr = ((ch - 8'd32) << 3) + row;
                glyph_row = font_rom(addr);
            end
        end
    endfunction

    function [7:0] display_byte;
        input [2:0] page;
        input [6:0] col;
        reg [1:0] line;
        reg [3:0] char_pos;
        reg [2:0] char_col;
        reg [7:0] ch;
        reg [7:0] rowbits;
        begin
            line     = page[2:1];
            char_pos = col[6:3];
            char_col = col[2:0];

            ch = text_char(line, char_pos);

            rowbits = glyph_row(ch, {page[0], 2'b00});
            display_byte[0] = rowbits[7-char_col];
            display_byte[1] = rowbits[7-char_col];

            rowbits = glyph_row(ch, {page[0], 2'b00} + 3'd1);
            display_byte[2] = rowbits[7-char_col];
            display_byte[3] = rowbits[7-char_col];

            rowbits = glyph_row(ch, {page[0], 2'b00} + 3'd2);
            display_byte[4] = rowbits[7-char_col];
            display_byte[5] = rowbits[7-char_col];

            rowbits = glyph_row(ch, {page[0], 2'b00} + 3'd3);
            display_byte[6] = rowbits[7-char_col];
            display_byte[7] = rowbits[7-char_col];

        end
    endfunction

    reg [31:0] pwr_cnt = 32'd0;
    reg [5:0]  init_idx = 6'd0;
    reg [2:0]  page = 3'd0;
    reg [7:0]  col = 8'd0;
    reg [4:0]  state = 5'd0;

    localparam ST_POWER     = 5'd0;
    localparam ST_INIT_SEND = 5'd1;
    localparam ST_INIT_WAIT = 5'd2;
    localparam ST_PAGE0     = 5'd3;
    localparam ST_PAGE0_W   = 5'd4;
    localparam ST_PAGE1     = 5'd5;
    localparam ST_PAGE1_W   = 5'd6;
    localparam ST_PAGE2     = 5'd7;
    localparam ST_PAGE2_W   = 5'd8;
    localparam ST_DATA      = 5'd9;
    localparam ST_DATA_W    = 5'd10;

    always @(posedge clk) begin
        tx_start <= 1'b0;

        case (state)
            ST_POWER: begin
                if (pwr_cnt == POWERON_WAIT-1)
                    state <= ST_INIT_SEND;
                else
                    pwr_cnt <= pwr_cnt + 32'd1;
            end

            ST_INIT_SEND: begin
                if (!tx_busy) begin
                    tx_ctrl  <= 8'h00;
                    tx_data  <= init_cmd(init_idx);
                    tx_start <= 1'b1;
                    state    <= ST_INIT_WAIT;
                end
            end

            ST_INIT_WAIT: begin
                if (tx_done) begin
                    if (init_idx == 6'd25) begin
                        page <= 3'd0;
                        col  <= 8'd0;
                        state <= ST_PAGE0;
                    end else begin
                        init_idx <= init_idx + 6'd1;
                        state <= ST_INIT_SEND;
                    end
                end
            end

            ST_PAGE0: begin
                if (!tx_busy) begin
                    tx_ctrl <= 8'h00;
                    tx_data <= 8'hB0 | {5'b00000, page};
                    tx_start <= 1'b1;
                    state <= ST_PAGE0_W;
                end
            end

            ST_PAGE0_W: begin
                if (tx_done)
                    state <= ST_PAGE1;
            end

            ST_PAGE1: begin
                if (!tx_busy) begin
                    tx_ctrl <= 8'h00;
                    tx_data <= 8'h00;
                    tx_start <= 1'b1;
                    state <= ST_PAGE1_W;
                end
            end

            ST_PAGE1_W: begin
                if (tx_done)
                    state <= ST_PAGE2;
            end

            ST_PAGE2: begin
                if (!tx_busy) begin
                    tx_ctrl <= 8'h00;
                    tx_data <= 8'h10;
                    tx_start <= 1'b1;
                    col <= 8'd0;
                    state <= ST_PAGE2_W;
                end
            end

            ST_PAGE2_W: begin
                if (tx_done)
                    state <= ST_DATA;
            end

            ST_DATA: begin
                if (!tx_busy) begin
                    tx_ctrl <= 8'h40;
                    tx_data <= display_byte(page, col[6:0]);
                    tx_start <= 1'b1;
                    state <= ST_DATA_W;
                end
            end

            ST_DATA_W: begin
                if (tx_done) begin
                    if (col == 8'd127) begin
                        col <= 8'd0;

                        if (page == 3'd7)
                            page <= 3'd0;
                        else
                            page <= page + 3'd1;

                        state <= ST_PAGE0;
                    end else begin
                        col <= col + 8'd1;
                        state <= ST_DATA;
                    end
                end
            end

            default: begin
                state <= ST_POWER;
            end
        endcase
    end

endmodule
