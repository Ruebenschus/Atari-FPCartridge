module top(
    input  wire       clk_25mhz,

    input  wire       btn_up,
    input  wire       btn_down,
    input  wire       btn_left,
    input  wire       btn_right,

    output wire [7:0] led,

    inout  wire       oled_scl,
    inout  wire       oled_sda,
    inout  wire       test_io,

    input  wire [15:1] cart_a,
    input  wire        rom3_n,
    input  wire        rom4_n,
    input  wire        uds_n,
    input  wire        lds_n,

    inout  wire [15:0] cart_d_out,
    output wire        dir4,
    output wire        oe4,
    output wire        dir5,
    output wire        oe5,

    output wire        pwr_ctl,
    input  wire        pwr_stat_n
);

    localparam [1:0] MAIN_CARTRIDGE = 2'd0;
    localparam [1:0] MAIN_DEBUG     = 2'd1;

    localparam [1:0] CART_DIAG    = 2'd0;
    localparam [1:0] CART_BEEP    = 2'd1;
    localparam [1:0] CART_ROMTEST = 2'd2;

    localparam [2:0] VIEW_MENU      = 3'd0;
    localparam [2:0] VIEW_CART_MENU = 3'd1;
    localparam [2:0] VIEW_DEBUG_MENU= 3'd2;
    localparam [2:0] VIEW_DIAG      = 3'd3;
    localparam [2:0] VIEW_DRIVE     = 3'd4;
    localparam [2:0] VIEW_READ      = 3'd5;

    localparam [14:0] ADDR_MAGIC_HI   = 15'h0000;
    localparam [14:0] ADDR_MAGIC_LO   = 15'h0001;
    localparam [14:0] ADDR_CODE_FIRST = 15'h0002;
    localparam [14:0] ADDR_CODE_LAST  = 15'h0031;
    localparam [14:0] ADDR_MODE_WORD  = 15'h0040;

    localparam [3:0] IDLE_HIT_TARGET = 4'd8;
    localparam [26:0] WAIT_POWER_TIMEOUT = 27'd125_000_000;
    localparam [26:0] WAIT_STEP_TIMEOUT  = 27'd25_000_000;

    localparam [6:0] OLED_ADDR = 7'h3C;
    localparam [24:0] TOGGLE_HALF_PERIOD = 25'd12_499_999;

    wire up_pulse;
    wire down_pulse;
    wire left_pulse;
    wire right_pulse;

    button_edge u_up (
        .clk(clk_25mhz),
        .btn_in(btn_up),
        .pulse(up_pulse)
    );

    button_edge u_down (
        .clk(clk_25mhz),
        .btn_in(btn_down),
        .pulse(down_pulse)
    );

    button_edge u_left (
        .clk(clk_25mhz),
        .btn_in(btn_left),
        .pulse(left_pulse)
    );

    button_edge u_right (
        .clk(clk_25mhz),
        .btn_in(btn_right),
        .pulse(right_pulse)
    );

    reg [24:0] blink_counter = 25'd0;
    always @(posedge clk_25mhz) begin
        blink_counter <= blink_counter + 25'd1;
    end

    reg [1:0] main_selected = MAIN_CARTRIDGE;
    reg [1:0] cart_menu_selected = CART_ROMTEST;
    reg       debug_menu_selected = 1'b0;
    reg [2:0] view_mode = VIEW_MENU;
    reg [1:0] cart_mode = CART_ROMTEST;
    reg       cart_armed = 1'b1;
    reg [4:0] drive_index = 5'd0;
    reg [5:0] read_select_index = 6'd0;

    reg       boot_magic_ok = 1'b0;
    reg       boot_magic_hi_ok = 1'b0;
    reg       boot_code_ok = 1'b0;
    reg       boot_idle_ok = 1'b0;
    reg [1:0] boot_phase = 2'd0;
    reg [3:0] idle_hits = 4'd0;
    reg [26:0] phase_wait_counter = 27'd0;
    reg        phase_error = 1'b0;
    reg [14:0] last_seen_addr = 15'd0;
    reg [14:0] trace_addr0 = 15'd0;
    reg [14:0] trace_addr1 = 15'd0;
    reg [14:0] trace_addr2 = 15'd0;
    reg [14:0] trace_addr3 = 15'd0;
    reg [2:0]  trace_count = 3'd0;

    wire cart_selected_raw = (~rom3_n) | (~rom4_n);
    wire cart_selected = cart_armed & cart_selected_raw;
    wire [14:0] word_addr = cart_a[15:1];

    reg        prev_cart_selected = 1'b0;
    reg [14:0] prev_word_addr = 15'd0;

    wire new_cart_cycle = cart_selected &&
                          (!prev_cart_selected || (word_addr != prev_word_addr));

    wire in_menu = (view_mode == VIEW_MENU);
    wire in_cart_menu = (view_mode == VIEW_CART_MENU);
    wire in_debug_menu = (view_mode == VIEW_DEBUG_MENU);
    wire diag_view = (view_mode == VIEW_DIAG);
    wire drive_view = (view_mode == VIEW_DRIVE);
    wire read_view = (view_mode == VIEW_READ);

    wire boot_analyzer_enable = (cart_mode == CART_DIAG);
    wire beep_enable = (cart_mode == CART_BEEP);
    wire custom_cart_enable = boot_analyzer_enable | beep_enable;

    wire [15:0] rom_data;
    wire [15:0] cart_d_in;
    wire        test_io_in;
    reg  [15:0] drive_data = 16'h0000;
    reg         read_value = 1'b0;
    reg  [24:0] drive_tick = 25'd0;
    reg         drive_level = 1'b0;

    cart_rom rom_inst (
        .clk(clk_25mhz),
        .addr(word_addr),
        .diag_rom_enable(custom_cart_enable),
        .beep_on(beep_enable),
        .data(rom_data)
    );

    assign cart_d_in = cart_d_out;
    assign test_io_in = test_io;
    assign cart_d_out = (drive_view || cart_selected) ?
                        (drive_view ? drive_data : rom_data) :
                        16'hzzzz;
    assign test_io = read_view ? drive_level : 1'bz;

    assign dir4 = read_view ? 1'b1 : 1'b0;
    assign dir5 = read_view ? 1'b1 : 1'b0;
    assign oe4  = (drive_view || read_view) ? 1'b0 : ~cart_selected;
    assign oe5  = (drive_view || read_view) ? 1'b0 : ~cart_selected;

    assign pwr_ctl = 1'b0;

    always @(*) begin
        drive_data = 16'h0000;
        if (drive_view && drive_level) begin
            case (drive_index)
                5'd0:  drive_data = 16'h0001;
                5'd1:  drive_data = 16'h0002;
                5'd2:  drive_data = 16'h0004;
                5'd3:  drive_data = 16'h0008;
                5'd4:  drive_data = 16'h0010;
                5'd5:  drive_data = 16'h0020;
                5'd6:  drive_data = 16'h0040;
                5'd7:  drive_data = 16'h0080;
                5'd8:  drive_data = 16'h0100;
                5'd9:  drive_data = 16'h0200;
                5'd10: drive_data = 16'h0400;
                5'd11: drive_data = 16'h0800;
                5'd12: drive_data = 16'h1000;
                5'd13: drive_data = 16'h2000;
                5'd14: drive_data = 16'h4000;
                default: drive_data = 16'h8000;
            endcase
        end
    end

    always @(*) begin
        case (read_select_index)
            6'd0:  read_value = cart_a[1];
            6'd1:  read_value = cart_a[2];
            6'd2:  read_value = cart_a[3];
            6'd3:  read_value = cart_a[4];
            6'd4:  read_value = cart_a[5];
            6'd5:  read_value = cart_a[6];
            6'd6:  read_value = cart_a[7];
            6'd7:  read_value = cart_a[8];
            6'd8:  read_value = cart_a[9];
            6'd9:  read_value = cart_a[10];
            6'd10: read_value = cart_a[11];
            6'd11: read_value = cart_a[12];
            6'd12: read_value = cart_a[13];
            6'd13: read_value = cart_a[14];
            6'd14: read_value = cart_a[15];
            6'd15: read_value = cart_d_in[0];
            6'd16: read_value = cart_d_in[1];
            6'd17: read_value = cart_d_in[2];
            6'd18: read_value = cart_d_in[3];
            6'd19: read_value = cart_d_in[4];
            6'd20: read_value = cart_d_in[5];
            6'd21: read_value = cart_d_in[6];
            6'd22: read_value = cart_d_in[7];
            6'd23: read_value = cart_d_in[8];
            6'd24: read_value = cart_d_in[9];
            6'd25: read_value = cart_d_in[10];
            6'd26: read_value = cart_d_in[11];
            6'd27: read_value = cart_d_in[12];
            6'd28: read_value = cart_d_in[13];
            6'd29: read_value = cart_d_in[14];
            6'd30: read_value = cart_d_in[15];
            6'd31: read_value = ~rom3_n;
            6'd32: read_value = ~rom4_n;
            6'd33: read_value = ~uds_n;
            6'd34: read_value = ~lds_n;
            default: read_value = 1'b0;
        endcase
    end

    task reset_diag_state;
        begin
            boot_magic_ok      <= 1'b0;
            boot_magic_hi_ok   <= 1'b0;
            boot_code_ok       <= 1'b0;
            boot_idle_ok       <= 1'b0;
            boot_phase         <= 2'd0;
            idle_hits          <= 4'd0;
            phase_wait_counter <= 27'd0;
            phase_error        <= 1'b0;
            last_seen_addr     <= 15'd0;
            trace_addr0        <= 15'd0;
            trace_addr1        <= 15'd0;
            trace_addr2        <= 15'd0;
            trace_addr3        <= 15'd0;
            trace_count        <= 3'd0;
        end
    endtask

    always @(posedge clk_25mhz) begin
        prev_cart_selected <= cart_selected;
        prev_word_addr <= word_addr;

        if (drive_tick == TOGGLE_HALF_PERIOD) begin
            drive_tick  <= 25'd0;
            drive_level <= ~drive_level;
        end else begin
            drive_tick <= drive_tick + 25'd1;
        end

        if (left_pulse) begin
            main_selected      <= MAIN_CARTRIDGE;
            cart_menu_selected <= cart_mode;
            debug_menu_selected<= 1'b0;
            view_mode          <= VIEW_MENU;
            cart_armed         <= 1'b1;
            read_select_index  <= 6'd0;
            reset_diag_state();
        end else if (in_menu) begin
            if (up_pulse || down_pulse) begin
                if (main_selected == MAIN_CARTRIDGE)
                    main_selected <= MAIN_DEBUG;
                else
                    main_selected <= MAIN_CARTRIDGE;
            end
        end else if (in_cart_menu) begin
            if (up_pulse) begin
                if (cart_menu_selected == CART_DIAG)
                    cart_menu_selected <= CART_ROMTEST;
                else
                    cart_menu_selected <= cart_menu_selected - 2'd1;
            end else if (down_pulse) begin
                if (cart_menu_selected == CART_ROMTEST)
                    cart_menu_selected <= CART_DIAG;
                else
                    cart_menu_selected <= cart_menu_selected + 2'd1;
            end
        end else if (in_debug_menu) begin
            if (up_pulse || down_pulse)
                debug_menu_selected <= ~debug_menu_selected;
        end else if (drive_view) begin
            if (up_pulse) begin
                if (drive_index == 5'd0)
                    drive_index <= 5'd15;
                else
                    drive_index <= drive_index - 5'd1;
            end else if (down_pulse) begin
                if (drive_index == 5'd15)
                    drive_index <= 5'd0;
                else
                    drive_index <= drive_index + 5'd1;
            end
        end else if (read_view) begin
            if (up_pulse) begin
                if (read_select_index == 6'd0)
                    read_select_index <= 6'd34;
                else
                    read_select_index <= read_select_index - 6'd1;
            end else if (down_pulse) begin
                if (read_select_index == 6'd34)
                    read_select_index <= 6'd0;
                else
                    read_select_index <= read_select_index + 6'd1;
            end
        end

        if (in_menu && right_pulse) begin
            if (main_selected == MAIN_CARTRIDGE) begin
                view_mode <= VIEW_CART_MENU;
                cart_menu_selected <= cart_mode;
            end else begin
                view_mode <= VIEW_DEBUG_MENU;
                debug_menu_selected <= 1'b0;
            end
        end else if (in_cart_menu && right_pulse) begin
            cart_mode <= cart_menu_selected;
            cart_armed <= 1'b1;
            if (cart_menu_selected == CART_DIAG) begin
                view_mode <= VIEW_DIAG;
                reset_diag_state();
            end else begin
                view_mode <= VIEW_MENU;
                reset_diag_state();
            end
        end else if (in_debug_menu && right_pulse) begin
            cart_armed <= 1'b0;
            if (debug_menu_selected == 1'b0)
                view_mode <= VIEW_DRIVE;
            else
                view_mode <= VIEW_READ;
        end

        if (diag_view && !boot_idle_ok) begin
            if (boot_phase == 2'd0) begin
                if (phase_wait_counter != WAIT_POWER_TIMEOUT)
                    phase_wait_counter <= phase_wait_counter + 27'd1;
                else
                    phase_error <= 1'b1;
            end else begin
                if (phase_wait_counter != WAIT_STEP_TIMEOUT)
                    phase_wait_counter <= phase_wait_counter + 27'd1;
                else
                    phase_error <= 1'b1;
            end
        end

        if (new_cart_cycle) begin
            last_seen_addr <= word_addr;

            if ((trace_count == 3'd0) ||
                ((word_addr != trace_addr0) &&
                 ((trace_count < 3'd2) || (word_addr != trace_addr1)) &&
                 ((trace_count < 3'd3) || (word_addr != trace_addr2)) &&
                 ((trace_count < 3'd4) || (word_addr != trace_addr3)))) begin
                case (trace_count)
                    3'd0: begin
                        trace_addr0 <= word_addr;
                        trace_count <= 3'd1;
                    end
                    3'd1: begin
                        trace_addr1 <= word_addr;
                        trace_count <= 3'd2;
                    end
                    3'd2: begin
                        trace_addr2 <= word_addr;
                        trace_count <= 3'd3;
                    end
                    3'd3: begin
                        trace_addr3 <= word_addr;
                        trace_count <= 3'd4;
                    end
                    default: begin
                    end
                endcase
            end

            if (diag_view) begin
                case (boot_phase)
                    2'd0: begin
                        if (word_addr == ADDR_MAGIC_HI) begin
                            boot_magic_hi_ok <= 1'b1;
                            boot_phase <= 2'd1;
                            phase_wait_counter <= 27'd0;
                            phase_error <= 1'b0;
                        end
                    end

                    2'd1: begin
                        if (word_addr == ADDR_MAGIC_LO) begin
                            boot_magic_ok <= 1'b1;
                            boot_phase <= 2'd2;
                            phase_wait_counter <= 27'd0;
                            phase_error <= 1'b0;
                        end
                    end

                    2'd2: begin
                        if (word_addr >= ADDR_CODE_FIRST && word_addr <= ADDR_CODE_LAST) begin
                            boot_code_ok <= 1'b1;
                            boot_phase <= 2'd3;
                            phase_wait_counter <= 27'd0;
                            phase_error <= 1'b0;
                        end
                    end

                    default: begin
                        if (word_addr == ADDR_MODE_WORD) begin
                            if (idle_hits != IDLE_HIT_TARGET)
                                idle_hits <= idle_hits + 4'd1;

                            if (idle_hits >= (IDLE_HIT_TARGET - 1'b1)) begin
                                boot_idle_ok <= 1'b1;
                                view_mode <= VIEW_MENU;
                                cart_armed <= 1'b1;
                                phase_wait_counter <= 27'd0;
                                phase_error <= 1'b0;
                            end
                        end else begin
                            idle_hits <= 4'd0;
                        end
                    end
                endcase
            end
        end
    end

    ssd1306_menu #(
        .CLK_HZ(25_000_000),
        .I2C_HZ(100_000),
        .OLED_ADDR(OLED_ADDR)
    ) u_oled (
        .clk(clk_25mhz),
        .main_selected(main_selected),
        .cart_selected(cart_menu_selected),
        .debug_selected(debug_menu_selected),
        .view_mode(view_mode),
        .cart_mode(cart_mode),
        .boot_magic_ok(boot_magic_ok),
        .boot_code_ok(boot_code_ok),
        .boot_idle_ok(boot_idle_ok),
        .usb_power(~pwr_stat_n),
        .drive_index(drive_index),
        .drive_level(drive_level),
        .read_index(read_select_index),
        .read_value(read_value),
        .test_io_in(test_io_in),
        .current_addr(last_seen_addr),
        .trace_addr0(trace_addr0),
        .trace_addr1(trace_addr1),
        .trace_addr2(trace_addr2),
        .trace_addr3(trace_addr3),
        .scl(oled_scl),
        .sda(oled_sda)
    );

    assign led[0] = (view_mode != VIEW_MENU);
    assign led[1] = diag_view ?
                    (boot_magic_hi_ok ? 1'b1 :
                     (boot_phase == 2'd0 ? (phase_error ? blink_counter[22] : blink_counter[24]) : 1'b0))
                    : 1'b0;
    assign led[2] = diag_view && boot_magic_hi_ok ?
                    (boot_magic_ok ? 1'b1 :
                     (boot_phase == 2'd1 ? (phase_error ? blink_counter[22] : blink_counter[24]) : 1'b0))
                    : 1'b0;
    assign led[3] = diag_view && boot_magic_ok ?
                    (boot_code_ok ? 1'b1 :
                     (boot_phase == 2'd2 ? (phase_error ? blink_counter[22] : blink_counter[24]) : 1'b0))
                    : 1'b0;
    assign led[4] = diag_view && boot_code_ok ?
                    (boot_idle_ok ? 1'b1 :
                     (boot_phase == 2'd3 ? (phase_error ? blink_counter[22] : blink_counter[24]) : 1'b0))
                    : 1'b0;
    assign led[5] = custom_cart_enable;
    assign led[6] = read_view ? read_value : cart_selected_raw;
    assign led[7] = drive_view ? test_io_in : ~pwr_stat_n;

    wire unused_byte_selects = uds_n & lds_n;
endmodule
