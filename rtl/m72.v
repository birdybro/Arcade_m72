`timescale 1 ns / 1 ns

module m72 (
	input clock,
	input sys_clk,
	input reset_n,
	
	input pixel_clock,
	
	input z80_reset_n,

	output [7:0] VGA_R,
	output [7:0] VGA_G,
	output [7:0] VGA_B,

	output VGA_HS,
	output VGA_VS,
	output VGA_HB,
	output VGA_VB,

	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,

	input        ioctl_wr,
	input [24:0] ioctl_addr,
	input [7:0]  ioctl_dout
);

/* Global signals from schematics */
wire M_IO = ~cpu_iorq; // high = memory low = IO
wire IOWR = cpu_iorq & cpu_we & stb; // IO Write
wire IORD = cpu_iorq & ~cpu_we & stb; // IO Read
wire MWR = ~cpu_iorq & cpu_we & stb; // Mem Write
wire MRD = ~cpu_iorq & ~cpu_we & stb; // Mem Read

reg wb_ack_o;
wire stb, cyc;
reg [19:0] pc;

wire [15:0] cpu_dout;
wire [19:1] cpu_addr;
wire [1:0] cpu_sel;
wire cpu_we;
wire cpu_iorq;
wire cpu_nmi;
wire cpu_nmi_ack;
wire cpu_int_rq;
wire cpu_int_ack;

// add 1 cycle wait to acknowledge
reg wb_ack_wait = 0;
always @(posedge clock or negedge reset_n)
begin
	if (!reset_n) begin
		wb_ack_o <= 0;
		wb_ack_wait <= 0;
	end else begin
		if (stb) wb_ack_wait <= ~wb_ack_wait;
		wb_ack_o <= stb & wb_ack_wait;
	end
end

zet zet_inst (
	.pc (pc),	// output [19:0]

	// Wishbone master interface
	.wb_clk_i ( clock ),		// input wb_clk_i
	.wb_rst_i ( !reset_n ),		// input wb_rst_i
	.wb_dat_i ( cpu_din ),		// input [15:0] wb_dat_i
	.wb_dat_o ( cpu_dout ),		// output [15:0] wb_dat_o
	.wb_adr_o ( cpu_addr ),			// output [19:1] wb_adr_o
	.wb_we_o  ( cpu_we ),			// output wb_we_o
	.wb_tga_o ( cpu_iorq ),		// output wb_tga_o
	.wb_sel_o ( cpu_sel ),		// output [1:0] wb_sel_o
	.wb_stb_o ( stb ),			// output wb_stb_o
	.wb_cyc_o ( cyc ),			// output wb_cyc_o
	.wb_ack_i ( wb_ack_o ),		// input wb_ack_i
	.wb_tgc_i ( cpu_int_rq ),			// input wb_tgc_i
	.wb_tgc_o ( cpu_int_ack ),			// output wb_tgc_o
	.nmi      ( cpu_nmi ),			// input nmi
	.nmia     ( cpu_nmi_ack )			// output nmia
);

wire [7:0] dout_h0, dout_l0, dout_h1, dout_l1, dout_hr, dout_lr;
wire ioctl_h0_cs, ioctl_h1_cs, ioctl_l0_cs, ioctl_l1_cs;
wire [3:0] ioctl_gfx_a_cs;
wire [3:0] ioctl_gfx_b_cs;

wire ls245_en, rom0_ce, rom1_ce, ram_cs2;

wire [15:0] rom_ram_data = rom0_ce ? { dout_h0, dout_l0 } :
							rom1_ce ? { dout_h1, dout_l1 } :
							ram_cs2 ? { dout_hr, dout_lr } : 16'hffff;

reg [15:0] pic;

wire [15:0] cpu_din =
	(vblank_trig && cpu_int_ack) ? 16'h0020 :
	(hint_trig && cpu_int_ack) ? 16'h0022 :
	ls245_en ? rom_ram_data :
	SW ? 16'hffff : // TODO player inputs
	FLAG ? 16'hffff : // TODO test, start and tnsl
	DSW ? 16'hffff : // TODO DIP Switches
	INTCS ? pic : // TODO PIC
	16'hffff;

always @(posedge clock or negedge reset_n) begin
	if (~reset_n) begin
		pic <= 0;
	end else begin
		if (cpu_we) begin
			if (INTCS)
				pic <= cpu_dout;
		end
	end
end

pal_3a pal_3a(
	.a(cpu_addr),
	.bank(),
	.dben(~stb),
	.m_io(~cpu_iorq),
	.cod(),
	.ls245_en(ls245_en),
	.rom0_ce(rom0_ce),
	.rom1_ce(rom1_ce),
	.ram_cs2(ram_cs2),
	.s(),
	.n_s()
);

wire SW, FLAG, DSW, SND, FSET, DMA_ON, ISET, INTCS;

pal_4d pal_4d(
    .M_IO(M_IO),
    .IOWR(IOWR),
    .IORD(IORD),
	.A(cpu_addr),
	.SW(SW),
	.FLAG(FLAG),
	.DSW(DSW),
	.SND(SND),
    .FSET(FSET),
    .DMA_ON(DMA_ON),
    .ISET(ISET),
    .INTCS(INTCS)
);

wire BUFDBEN, BUFCS, OBJ_P, CHARA_P, CHARA, SOUND, SDBEN;

pal_3d pal_3d(
	.A(cpu_addr),
    .M_IO(~cpu_iorq),
    .DBEN(~stb),
    .TNSL(), // TODO
    .BRQ(), // TODO

	.BUFDBEN(BUFDBEN),
	.BUFCS(BUFCS),
	.OBJ_P(OBJ_P),
	.CHARA_P(CHARA_P),
    .CHARA(CHARA),
    .SOUND(SOUND),
    .SDBEN(SDBEN)
);

download_selector download_selector(
	.ioctl_addr(ioctl_addr),
	.h0_cs(ioctl_h0_cs),
	.h1_cs(ioctl_h1_cs),
	.l0_cs(ioctl_l0_cs),
	.l1_cs(ioctl_l1_cs),
	.gfx_a_cs(ioctl_gfx_a_cs),
	.gfx_b_cs(ioctl_gfx_b_cs)
);

eprom_64 rom_h0(
	.clk(clock),
	.addr(cpu_addr[16:1]),
	.data(dout_h0),

	.clk_in(sys_clk),
	.addr_in(ioctl_addr[15:0]),
	.data_in(ioctl_dout),
	.wr_in(ioctl_wr),
	.cs_in(ioctl_h0_cs)
);

eprom_64 rom_l0(
	.clk(clock),
	.addr(cpu_addr[16:1]),
	.data(dout_l0),

	.clk_in(sys_clk),
	.addr_in(ioctl_addr[15:0]),
	.data_in(ioctl_dout),
	.wr_in(ioctl_wr),
	.cs_in(ioctl_l0_cs)
);

eprom_64 rom_h1(
	.clk(clock),
	.addr(cpu_addr[16:1]),
	.data(dout_h1),

	.clk_in(sys_clk),
	.addr_in(ioctl_addr[15:0]),
	.data_in(ioctl_dout),
	.wr_in(ioctl_wr),
	.cs_in(ioctl_h1_cs)
);

eprom_64 rom_l1(
	.clk(clock),
	.addr(cpu_addr[16:1]),
	.data(dout_l1),

	.clk_in(sys_clk),
	.addr_in(ioctl_addr[15:0]),
	.data_in(ioctl_dout),
	.wr_in(ioctl_wr),
	.cs_in(ioctl_l1_cs)
);

dpramv #(.widthad_a(13)) ram_h
(
	.clock_a(clock),
	.address_a(cpu_addr[13:1]),
	.q_a(dout_hr),
	.wren_a(ram_cs2 & cpu_we & cpu_sel[1] & ls245_en),
	.data_a(cpu_dout[15:8]),

	.clock_b(clock),
	.address_b(),
	.data_b(),
	.wren_b(),
	.q_b()
);

dpramv #(.widthad_a(13)) ram_l
(
	.clock_a(clock),
	.address_a(cpu_addr[13:1]),
	.q_a(dout_lr),
	.wren_a(ram_cs2 & cpu_we & cpu_sel[0] & ls245_en),
	.data_a(cpu_dout[7:0]),

	.clock_b(clock),
	.address_b(),
	.data_b(),
	.wren_b(),
	.q_b()
);

/*
pic pic_inst (
	.clk( clock ),					// input clk
	.reset( !reset_n ),				// input reset
	.cs( pic_cs ),					// input cs
	.data_m_data_in( dat_o ),		// input [15:0] data_m_data_in
	.data_m_data_out( pic_dout ),	// output [15:0] data_m_data_out
	.data_m_bytesel( sel ),			// input [1:0] data_m_bytesel
	.data_m_wr_en( we ),			// input data_m_wr_en
	.data_m_access( stb ),			// input data_m_access
	.data_m_ack( pic_data_ack ),	// output data_m_ack
	.intr_in( pic_intr_in ),		// input [7:0] intr_in
	.irq( pic_irq_vec ),			// output [7:0] irq
	.intr( intr ),					// output intr
	.inta( inta )					// input inta
);
*/

reg vblank_trig;
reg hint_trig;
reg old_vblk, old_hint;
assign cpu_int_rq = (vblank_trig | hint_trig);
always @(posedge clock or negedge reset_n) begin
	if (!reset_n) begin
		vblank_trig <= 1'b0;
		hint_trig <= 1'b0;
		old_vblk <= 1'b0;
		old_hint <= 1'b0;
	end
	else begin
		old_vblk <= VBLK;
		old_hint <= HINT;

		if (VBLK & ~old_vblk) vblank_trig <= 1'b1;
		if (HINT & ~old_hint) hint_trig <= 1'b1;
		if (vblank_trig && cpu_int_ack) vblank_trig <= 1'b0;
		if (hint_trig && cpu_int_ack) hint_trig <= 1'b0;
		
		if (cpu_int_ack && stb) begin
			vblank_trig <= 1'b0;
			hint_trig <= 1'b0;
		end
	end
end


/*wire [15:0] wb_dat_i = (vblank_trig && inta) ? 16'h0020 :
					     (hint_trig && inta) ? 16'h0022 :
											   dat_i;*/

/*
wire [15:0] z80_addr;
wire [7:0] z80_di = sound_ram[ z80_addr ];
wire [7:0] z80_do;

wire [7:0] z80_dinst = 8'h00;	// M1 vector fetch?
wire [6:0] z80_mc;
wire [6:0] z80_ts;

wire z80_cen = 1'b1;
wire z80_wait_n = 1'b1;
wire z80_int_n = 1'b1;
wire z80_nmi_n = 1'b1;
wire z80_busrq_n = 1'b1;


tv80_core tv80_core_inst (
  // Inputs
  .reset_n( z80_reset_n ),
  .clk( clock ),				// Change to sound clock later!
  
  .cen( z80_cen ),
  .wait_n( z80_wait_n ),
  .int_n( z80_int_n ),
  .nmi_n( z80_nmi_n ),
  .busrq_n( z80_busrq_n ),	
  .dinst( z80_dinst ),			// input [7:0] M1 vector fetch?
  .di( z80_di ),				// input [7:0] di

  .m1_n( z80_m1_n ),
  .iorq( z80_iorq ),
  .no_read( z80_no_read ),
  .write( z80_write ), 
  .rfsh_n( z80_rfsh_n ),
  .halt_n( z80_halt_n ),
  .busak_n( z80_busak_n ),
  .A( z80_addr ),
  .dout( z80_do ),
  .mc( z80_mc ),				// output [6:0] mc.
  .ts( z80_ts ),				// output [6:0] ts.
  .intcycle_n( z80_intcycle_n ),
  .IntE( z80_IntE ),
  .stop( z80_stop )
);

reg [7:0] sound_ram [0:65535];

// Change to sound clock later!
always @(posedge clock or negedge z80_reset_n)
begin
	if (!z80_reset_n) begin

	end
	else begin
		if (!z80_m1_n & z80_write) sound_ram[ z80_addr ] <= z80_do;
	end
end
*/

wire [8:0] VE, V;
wire [9:0] HE, H;
wire HBLK, VBLK, HS, VS;
wire INT_D, HINT;

assign VGA_HS = HS;
assign VGA_HB = HBLK;
assign VGA_VS = VS;
assign VGA_VB = VBLK;

kna70h015 kna70h015(
	.DCLK(pixel_clock),
	.D(cpu_dout),
	.ISET(ISET),
	.NL(0),
	.S24H(0),

	.CLD_UNKNOWN(),
	.CPBLK(),

	.VE(VE),
	.V(V),
	.HE(HE),
	.H(H),

	.HBLK(HBLK),
	.VBLK(VBLK),
	.INT_D(INT_D),
	.HINT(HINT),

	.HS(HS),
	.VS(VS)
);

board_b_d board_b_d(
    .sys_clk(sys_clk),
    .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),

    .gfx_a_cs(ioctl_gfx_a_cs),
    .gfx_b_cs(ioctl_gfx_b_cs),

    .DCLK(pixel_clock),

    .DOUT(),

    .DIN(cpu_dout),
    .A(cpu_addr),
    .BYTE_SEL(cpu_sel),
    .MRD(MRD),
    .MWR(MWR),
    .IORD(IORD),
    .IOWR(IOWR),
    .CHARA(CHARA),
    .NL(),

    .VE(VE),
    .HE(HE),

	.RED(VGA_R),
	.GREEN(VGA_G),
	.BLUE(VGA_B)
);

endmodule
