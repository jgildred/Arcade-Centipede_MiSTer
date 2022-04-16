//
// Atari Centipede, from the schematics
//
// Brad Parker <brad@heeltoe.com> 10/2015
//
// The 6502 cpu used here is not completely cycle accurate in relation to the original "real" 6502.
// Specifically, the game makes heavy use of the knowledge about when i/o space read/writes will
// occur in relationship to the cpu clocks, specially phi2.  The game hardware was set up to allow
// the cpu accces on the back side of the s_4h signal, which, based on phi0, phi2 and the mpuclk was
// when the original (i.e. real) 6502 would assert i/o signals.  Rather than fight this battle I made
// the playfield a ram synchronous dual port memory, which was natural in a modern FPGA.  This eliminated
// the contention and allowed me to remove the s_4h qualifiers from the address generation.
//
// The game code also relies on the pokey's random number generation working correctly and caused me to
// do some debugging of the pokey code I was using.
//

`timescale 1 ps / 1 ps
	
module centipede(
		input         clk_12mhz,
		input         reset,
		input         pause,
		input         milli,
		input [9:0]   playerinput_i,
		input [7:0]   trakball_i,
		output        flip_o,
		input [7:0]   joystick_i,
		input [23:0]   sw1_i,
		input [23:0]   sw2_i,
		input  [15:0] dn_addr,
		input  [7:0]  dn_data,
		input					dn_wr,
		input 				v_flip,
		input 				h_flip,
		output [4:1]  led_o,
		output [8:0]  rgb_o,
		output        sync_o,
		output        hsync_o,
		output        vsync_o,
		output        hblank_o,
		output        vblank_o,
		output [7:0]  audio_o,
		output        clk_6mhz_o,

		 // Hiscore

		 input	[5:0]	hs_address,
		 input	[7:0]	hs_data_in,
		 output	[7:0]	hs_data_out,
		 input			hs_write
	);

	 //
	 wire s_12mhz;
	 wire s_6mhz, s_6mhz_n, s_6mhz_n_en;

	 wire phi0, phi2, phi0_en;
	 reg 	phi0a, phi0a_temp;

	 //
	 reg rom_n;
	 reg ram0_n;
	 reg steerclr_n, watchdog_n, out0_n, irqres_n;
	 reg pokey_n, pokey2_n, swrd_n, pf_n;
	 reg coloram_n, ea_read_n, ea_ctrl_n, ea_addr_n;
	 reg in0_n, in1_n;

	 reg pframrd_n;
	 reg pfwr3_n, pfwr2_n, pfwr1_n, pfwr0_n;
	 reg pfrd3_n, pfrd2_n, pfrd1_n, pfrd0_n;

	 wire [9:0] adecode;
	 wire       pac_n;

	 wire       mpu_clk;
	 reg [7:0]  mpu_reset_cntr;
	 reg 	      mpu_reset;
	 wire       mpu_reset_n;
	 reg 	      irq;
	 wire       rw_n;

	 wire [15:0] ab;
	 
	 wire [23:0] db_in;
	 wire [7:0] db_out;

	 wire [7:0] ram_out;
	 wire [7:0] rom_out;
	 
	 //
	 wire [7:0] vprom_addr;
	 wire [3:0] vprom_out;
	 reg [3:0]  vprom_reg;
	 
	 wire       vsync, vblank, hblank, vreset;
	 reg 	      hsync;
	 wire       vsync_n, hsync_n, vblank_n, hblank_n, vreset_n;
	 wire       hsync_reset;
	 
    wire       s_1h, s_2h, s_4h, s_8h, s_16h, s_32h, s_64h, s_128h, s_256h;
    wire       s_1h_en, s_4h_en, s_8h_en, s_32h_en;
    wire       s_1v, s_2v, s_4v, s_8v, s_16v, s_32v, s_64v, s_128v;
    wire       s_16v_en;
	
    wire       s_4h_n, s_8h_n, s_256h_n;
    wire       s_4h_n_en, s_256h_n_en;
	 wire       s_256hd_n;
	 wire       s_256h2d_n;
	 wire	      vblankd_n;
	 wire       s_6_12;
	 
	 reg 	      s_256h2d;
	 reg 	      s_256hd;
	 reg 	      vblankd;
	 
	 wire       pload_n;
	 wire       write_n;
	 wire       brw_n;
	 
	 //
	 wire [7:0]  match_line;
	 wire [7:0]  match_sum;
	 wire        match_sum_top;
	 reg [5:0]   match_sum_hold;
				 
	 wire [3:0]  match_mux;
	 wire        match_n;
	 wire        match_true;
	 wire [3:0]  mga;

	 //
	 wire [7:0]  pf;
	 wire [1:0]  pf_sel;
	 wire [3:0]  pfa7654, pfa3210;
	 wire [7:0]  pfa;
	 wire [7:0]  pf_out;
	 wire        pf_addr_stamp;

	 wire [31:0] pfd;
	 reg [31:16] pfd_hold;
	 reg [31:16] pfd_hold2;

	 reg [1:0]   gry;
	 wire [1:0]  y;
	 reg [1:0]   mr;
	 
	 wire [7:0]  line_ram_addr;
	 reg [1:0]   line_ram[0:255];
	 reg [7:0]   line_ram_ctr;
	 wire        line_ram_ctr_load;
	 wire        line_ram_ctr_clr;

	 //
	 wire [7:0]  pf_mux1, pf_mux0;
	 reg [7:0]   pf_shift1, pf_shift0;
	 reg [1:0]   area;

	 wire [10:0] pf_rom1_addr, pf_rom0_addr;
	 wire [7:0]  pf_rom1_out_raw, pf_rom0_out_raw;
	 wire [7:0]  pf_rom1_out, pf_rom0_out;
	 wire [7:0]  pf_rom1_out_rev, pf_rom0_out_rev;

	 reg [7:0]   pic, picD;
	 
	 reg 	       hs;
	 wire        hs_set;
	 //
	 wire        comp_sync;
	 reg [7:0]   rgbi;
	 wire [7:0]  coloram_out;
	 wire [7:0]  coloram_rgbi;
	 wire        coloram_w_n;
	 reg 	       coloren, coloren_temp;

	 wire [5:0]  audio;

	 //
	 wire        mob_n;
	 wire        blank_clk;

	 //
	 wire [7:0]  joystick_out;
	 wire [3:0]  tra, trb;
	 wire        dir1, dir2;

	 wire [23:0]  switch_out;
	 wire        flip;
	 wire        cntrlsel;
	 wire        coin_ctr_r_drive, coin_ctr_c_drive, coin_ctr_l_drive;
	 wire [7:0]  playerin_out;

	 wire [7:0]  pokey_out;
	 wire [7:0]  pokey2_out;
	 wire [3:0]  pokey_ch0, pokey_ch1, pokey_ch2, pokey_ch3; 
	 wire [3:0]  pokey2_ch0, pokey2_ch1, pokey2_ch2, pokey2_ch3;
 
	 // ------------------------------------------------------------------------

	 // Synchronizer
	 reg [11:0]  h_counter;
	 reg [7:0]   v_counter;
	 wire        v_counter_reset;
	
	 always @(posedge s_12mhz or posedge reset) // ??? Mist removed 'or posedge reset'
		 if (reset)
			 h_counter <= 12'b1101_0000_0000; // ??? Mist sets to 0 here
		 else
			 if (h_counter == 12'hfff)
	          h_counter <= 12'b1101_0000_0000;
			 else
	          h_counter <= h_counter + 12'd1;

	 assign s_6mhz = h_counter[0];
	 assign s_6mhz_en = !h_counter[0];
	 assign s_1h   = h_counter[1];
	 assign s_1h_en = h_counter[1:0] == 2'b01;
	 assign s_2h   = h_counter[2];
	 assign s_4h   = h_counter[3];
	 assign s_4h_en = h_counter[3:0] == 4'b0111;
	 assign s_8h   = h_counter[4];
	 assign s_8h_en = h_counter[4:0] == 5'b01111;
	 assign s_16h  = h_counter[5];
	 assign s_32h  = h_counter[6];
	 assign s_32h_en = h_counter[6:0] == 7'b0111111;
	 assign s_64h  = h_counter[7];
	 assign s_128h = h_counter[8];
	 assign s_256h = h_counter[9];
	 
	assign s_4h_n = ~s_4h;
	assign s_4h_n_en = h_counter[3:0] == 4'b1111;
	assign s_8h_n = ~s_8h;
	assign s_256h_n = ~s_256h;
	assign s_256h_n_en = h_counter[9:0] == 10'b1111111111;
	
	assign pload_n = ~(s_1h & s_2h & s_4h);
	
	assign s_12mhz = clk_12mhz;
	assign s_12mhz_n = ~clk_12mhz;
	assign s_6mhz_n = ~s_6mhz;
	assign s_6mhz_n_en = h_counter[0];

   assign v_counter_reset = reset | ~vreset == 0;

	 // Mister version
	 always @(posedge s_256h_n or posedge reset)  // ??? Mist removed 'or posedge reset'
	 	 if (reset)
	 		 v_counter <= 0;
	 	 else
			 /* ld# is on positive clock edge */
	 		 if (vreset_n == 0)
	           v_counter <= 0;
	 		 else
	           v_counter <= v_counter + 8'd1;
	 
	 // Mist version
	 //always @(posedge s_12mhz)
    // if (reset)
    //   v_counter <= 0;
    // else if (s_256h_n_en)
       /* ld# is on positive clock edge */
    //   if (vreset == 1)
    //     v_counter <= 0;
    //   else
    //     v_counter <= v_counter + 8'd1;
	 
	 assign s_1v   = v_counter[0];
	 assign s_2v   = v_counter[1];
	 assign s_4v   = v_counter[2];
	 assign s_8v   = v_counter[3];
	 assign s_16v  = v_counter[4];
	 assign s_16v_en = s_256h_n_en & v_counter[4:0] == 5'b01111;
	 assign s_32v  = v_counter[5];
	 assign s_64v  = v_counter[6];
	 assign s_128v = v_counter[7];
	 
	 assign mob_n = ~((s_256h_n & s_256hd) | (s_256h2d_n & s_256hd)) | milli;
	 assign blank_clk = ~s_12mhz & (h_counter[3:0] == 4'b1111);

	 // ??? mist code is 'always @(posedge s_12mhz)'
	 always @(posedge blank_clk or posedge reset)
		 if (reset)
			begin
				s_256h2d <= 1'b0;
				s_256hd <= 1'b0;
				vblankd <= 1'b0;
			end
		 else  // Mister version
		 //else if (h_counter[3:0] == 4'b1111) // Mist version
			begin
				s_256h2d <= s_256hd;
				s_256hd <= s_256h;
				vblankd <= vblank;
			end

	 assign s_256h2d_n = ~s_256h2d;
	 assign s_256hd_n = ~s_256hd;
	 assign vblankd_n = ~vblankd;
	 assign vprom_addr = {vblank, s_128v, s_64v, s_32v, s_8v, s_4v, s_2v, s_1v};

	 wire [3:0] scrap;

	 // ??? different values than what mist uses
	 dpram #(8) vprom
	 (
				.clock_a(clk_12mhz),
				.enable_a(1'b1),
				.wren_a(dn_wr && prom_cs),
				.address_a(dn_addr[7:0]),
				.data_a(dn_data),
				.q_a(),

				.clock_b(clk_12mhz),
				.enable_b(s_6mhz),
				.address_b(vprom_addr),
				.wren_b(),
				.data_b(),
				.q_b({scrap,vprom_out})
	 );
	 
	 // Mister version
	 always @(posedge s_256h_n or posedge reset)
	 	 if (reset)
	 		 vprom_reg <= 0;
	 	 else
	 		 vprom_reg <= vprom_out;
	 
	 // Mist version
    //always @(posedge s_12mhz)
	//	if (reset)
	//		vprom_reg <= 0;
	//	else if (s_256h_n_en)
	//		vprom_reg <= vprom_out;
	//		else if (s_256h_n_en)
	//			vprom_reg <= vprom_out;

	 assign vsync = vprom_reg[0];
	 assign vsync_n = ~vprom_reg[0];

	 assign vreset = vprom_reg[2];
	 assign vreset_n = ~vprom_reg[2];

	 assign vblank = vprom_reg[3];
	 assign vblank_n = ~vprom_reg[3];

	 assign hs_set = reset | ~s_256h_n;
	 
	 always @(posedge s_32h or posedge hs_set)
		 if (hs_set)
			 hs <= 1;
		 else
			 hs <= s_64h;

	 assign hsync_reset = reset | hs;
	 
	 always @(posedge s_8h or posedge hsync_reset)
		 if (hsync_reset)
			 hsync <= 0;
		 else
			 hsync <= s_32h;

	 assign hsync_n = ~hsync;
	 

	 always @(posedge s_6mhz)
		 if (reset)
			 coloren_temp <= 0;
		 else
			 coloren_temp <= s_256hd;
	
	// Mister version	
	always @(negedge s_6mhz)
		 if (reset)
			 coloren <= 0;
		 else
			 coloren <= coloren_temp;
	
	// Mist version
	//always @(posedge s_12mhz)
	//	if (reset)
	//		coloren <= 0;
	//	else if (s_6mhz_en)
	//		coloren <= s_256hd;

	 assign s_6_12 = ~(s_6mhz & s_12mhz);

	 reg xxx1;
	 
	 // Mister version
	 always @(posedge s_6_12)
	 	 if (reset)
	 		 xxx1 <= 0;
	 	 else
	 		 xxx1 <= coloren;
	 
	 // Mist version
	 //always @(posedge s_12mhz)//s_6_12)
	//	if (reset)
	//		xxx1 <= 0;
	//	else if (s_6mhz_en)
	//		xxx1 <= coloren;
	
	// Mist includes this code
	//reg hblank1_n;
   //always @(posedge s_12mhz)
   //if (reset)
   //   hblank1_n <= 0;
   //else if (s_6mhz_n_en)
   //   hblank1_n <= s_256hd;
			
	 //assign vblank = vprom_reg[3]; // Added on Mist
	 assign hblank_n = ~(~xxx1 & ~coloren); // Mist removed this line, but removing breaks centipede
	 assign hblank = ~hblank_n;

	/*
		Centipede ROMs
		136001-407.d1	2048	0		0000 0000 00000000 prog_rom_1
	136001-408.e1	2048	2048		0000 1000 00000000 prog_rom_1
	136001-409.fh1	2048	4096		0001 0000 00000000 prog_rom_1
	136001-410.j1	2048	6144		0001 1000 00000000 prog_rom_1
	136001-211.f7	2048	8192		0010 0000 00000000 prog pf_rom_0
	136001-212.hj7	2048	10240		0010 1000 00000000 prog pf_rom_1
	136001-213.p4	256	12288		0011 0000 00000000 prom_cs
	*/

	// ROM upload enables
	wire prog_rom_1_cs = (dn_addr[13] == 1'b0);
	wire prog_pf_rom_0_cs = (dn_addr[13:11]==3'b100);
	wire prog_pf_rom_1_cs = (dn_addr[13:11]==3'b101);
	wire prom_cs = (dn_addr[13:8]==6'b110000);
	
	// Mist versions (breaks Centipede and doesn't fix Millipede)
	//wire prog_rom_1_cs = (!dn_addr[14]);
	//wire prog_pf_rom_0_cs = (dn_addr[14:11]==4'b1000);
	//wire prog_pf_rom_1_cs = (dn_addr[14:11]==4'b1001);
	//wire prom_cs = (dn_addr[14:8]==7'b1010000);

	// Program ROM
	dpram #(13) rom
	(
		.clock_a(clk_12mhz),
		.enable_a(1'b1),
		.wren_a(dn_wr && prog_rom_1_cs),
		.address_a(dn_addr[12:0]),
		.data_a(dn_data),
		.q_a(),

		.clock_b(clk_12mhz),
		.enable_b(s_6mhz),
		.address_b(ab[12:0]),
		.wren_b(),
		.data_b(),
		.q_b(rom_out)
	);

	// CPU RAM
		spram #(10,8) ram(
			.clock(clk_12mhz),
			.enable(s_6mhz && !ram0_n),
			.address(ab[9:0]),
			.data(db_out),
			.q(ram_out),
			.wren(~write_n)
	);

	wire irq_n;
	 
	// Mister version
	always @(posedge s_16v or negedge irqres_n)
	 	 if (~irqres_n)
	 		 irq <= 1'b1;
	 	 else
	 		 irq <= ~s_32v;
	 
	// Mist version
	//always @(posedge s_12mhz or negedge irqres_n)
	//	  if (~irqres_n)
	//		 irq <= 1'b1;
	//	  else if (s_16v_en)
	//		 irq <= ~s_32v;

	assign irq_n = irq;

	// ??? This is not in Mist version
	always @(posedge s_1h)
		if (reset)
			phi0a_temp <= 1'b0;
		else
			case ({(pf_n | s_4h), s_2h})
			2'b00: phi0a_temp <= phi0a_temp; // ??? remove?
			2'b01: phi0a_temp <= 1'b0;
			2'b10: phi0a_temp <= 1'b1;
			2'b11: phi0a_temp <= ~phi0a_temp;
			endcase

	// Mister version
	always @(negedge s_1h)
		if (reset)
			phi0a <= 1'b0;
		else
			phi0a <= phi0a_temp;
	
	// Mist version
	//always @(posedge s_12mhz)
   //  if (reset)
   //    phi0a <= 1'b0;
   //  else if (s_1h_en)
   //    phi0a <= ~phi0a;

	assign phi0 = ~phi0a;
	assign pac_n = ~phi0a;
	assign phi0_en = s_1h_en & phi0a;
	
	// watchdog?
	always @(posedge s_12mhz)
		if (reset)
			begin
				mpu_reset <= 1;
				mpu_reset_cntr <= 0;
			end
		else
			begin
			if (mpu_reset_cntr != 8'h10)
				mpu_reset_cntr <= mpu_reset_cntr + 8'd1;
			else
				mpu_reset <= 0;
			end

	assign mpu_clk = s_6mhz;
	assign mpu_reset_n = ~mpu_reset;

	//assign phi2 = ~phi0;
	// T65 cpu(
	// 	.mode(0),
	// 	.res_n(mpu_reset_n),
	// 	.enable(1),
	// 	.clk(phi0),
	// 	.rdy(~pause),
	// 	.abort_n(1),
	// 	.irq_n(irq_n),
	// 	.nmi_n(1),
	// 	.so_n(1),
	// 	.r_w_n(rw_n),
	// 	.a(ab),
	// 	.di(db_in),
	// 	.do(db_out)
	// );
	 p6502 p6502(
		.clk(mpu_clk),
		.reset_n(mpu_reset_n),
		.nmi(1'b1),
		.irq(irq_n),
		.so(1'b0),
		.rdy(~pause),
		.phi0(phi0),
		.phi2(phi2),
		.rw_n(rw_n),
		.a(ab),
		.din(db_in),
		.dout(db_out)
	);


	 // Address Decoder
	assign write_n = ~(phi2 & ~rw_n);
	assign brw_n = ~rw_n;
	//assign rom_n = brw_n | ~ab[13]; // already handled below

	//   1111 11
	//   5432 1098 7654 3210
	//
	//   0010 xxxx xxxx xxxx  2000 rom_n
	//   0000 1100 0000 0000  0c00 

	assign adecode =
		(ab[13:10] == 4'b0000) ? 10'b1111111110 :
		(ab[13:10] == 4'b0001) ? 10'b1111111101 :
		(ab[13:10] == 4'b0010) ? 10'b1111111011 :
		(ab[13:10] == 4'b0011) ? 10'b1111110111 :
		(ab[13:10] == 4'b0100) ? 10'b1111101111 :
		(ab[13:10] == 4'b0101) ? 10'b1111011111 :
		(ab[13:10] == 4'b0110) ? 10'b1110111111 :
		(ab[13:10] == 4'b0111) ? 10'b1101111111 :
		(ab[13:10] == 4'b1000) ? 10'b1011111111 :
		(ab[13:10] == 4'b1001) ? 10'b0111111111 :
		10'b1111111111;

	wire write2_n = ~(s_6mhz & ~write_n);
	
	  // For millipede
   wire   mos_n = ab[14:12] != 3'b000;
   wire   io_n  = ab[14:12] != 3'b010;
   wire   inputs_n  = {io_n, ab[11:10]} != 3'b000;
   wire   outputs_n = {io_n, ab[11:10]} != 3'b001;
	
	// Set game mode
	//always @(posedge clk_sys) 
	//begin
		// if (ioctl_wr && (ioctl_index==8'd1)) game_mode <= ioctl_dout[3:0];
	//end

   always @(*) begin
      if (milli) begin
         rom_n = brw_n | ~ab[14];

         steerclr_n = 1; // adecode[9] | write2_n;

         in0_n =     {inputs_n, ab[5:4]} != 3'b000;
         in1_n =     {inputs_n, ab[5:4]} != 3'b001;
         ea_read_n = {inputs_n, ab[5:4]} != 3'b011;

         swrd_n   = 1;//adecode[2];
         pf_n     = ab[14:12] != 3'b001; // _scram
         ram0_n   = {mos_n, ab[11:10]} != 3'b000;
         pokey_n  = {mos_n, ab[11:10]} != 3'b001;
         pokey2_n = {mos_n, ab[11:10]} != 3'b010;

         coloram_n  = {outputs_n | write_n, ab[9:7]} != 4'b0001;
         out0_n     = {outputs_n | write_n, ab[9:7]} != 4'b0010;
         irqres_n   = {outputs_n | write_n, ab[9:7]} != 4'b0100 & mpu_reset_n;
         watchdog_n = {outputs_n | write_n, ab[9:7]} != 4'b0101;
         ea_ctrl_n  = {outputs_n | write_n, ab[9:7]} != 4'b0110;
         ea_addr_n  = {outputs_n | write_n, ab[9:7]} != 4'b0111;

         pframrd_n = pf_n | brw_n;
	
	      {pfwr3_n, pfwr2_n, pfwr1_n, pfwr0_n} =
					({pf_n, write_n, ab[5:4]} == 4'b0000) ? 4'b1110 :
					({pf_n, write_n, ab[5:4]} == 4'b0001) ? 4'b1101 :
					({pf_n, write_n, ab[5:4]} == 4'b0010) ? 4'b1011 :
					({pf_n, write_n, ab[5:4]} == 4'b0011) ? 4'b0111 :
					4'b1111;

         {pfrd3_n, pfrd2_n, pfrd1_n, pfrd0_n} =
						(ab[5:4] == 2'b00) ? 4'b1110 :
						(ab[5:4] == 2'b01) ? 4'b1101 :
						(ab[5:4] == 2'b10) ? 4'b1011 :
						(ab[5:4] == 2'b11) ? 4'b0111 :
						4'b1111;
      end else begin
         rom_n = brw_n | ~ab[13];

         steerclr_n = adecode[9] | write2_n;
         watchdog_n = adecode[8] | write2_n;
         out0_n =     adecode[7] | write2_n;
         irqres_n =  (adecode[6] | write2_n) & mpu_reset_n;
	
	      coloram_n = (adecode[5] | ab[9]) /* | pac_n*/;
			
	      pokey_n = adecode[4];
	      pokey2_n = 1; // adecode[3];
			
	      in0_n =   adecode[3] | ab[1];
	      in1_n =   adecode[3] | ~ab[1];
			
	      swrd_n =  adecode[2];
	      pf_n =    adecode[1];
	      ram0_n =  adecode[0];

	      {ea_read_n, ea_ctrl_n, ea_addr_n} =
					({~ab[9]|adecode[5], ab[8:7]} == 3'b000) ? 3'b110 :
					({~ab[9]|adecode[5], ab[8:7]} == 3'b001) ? 3'b101 :
					({~ab[9]|adecode[5], ab[8:7]} == 3'b010) ? 3'b011 :
					3'b111;
	      pframrd_n = pf_n | brw_n;
	 
	      {pfwr3_n, pfwr2_n, pfwr1_n, pfwr0_n} =
					({pf_n, write_n, ab[5:4]} == 4'b0000) ? 4'b1110 :
					({pf_n, write_n, ab[5:4]} == 4'b0001) ? 4'b1101 :
					({pf_n, write_n, ab[5:4]} == 4'b0010) ? 4'b1011 :
					({pf_n, write_n, ab[5:4]} == 4'b0011) ? 4'b0111 :
					4'b1111;

	      {pfrd3_n, pfrd2_n, pfrd1_n, pfrd0_n} =
						(ab[5:4] == 2'b00) ? 4'b1110 :
						(ab[5:4] == 2'b01) ? 4'b1101 :
						(ab[5:4] == 2'b10) ? 4'b1011 :
						(ab[5:4] == 2'b11) ? 4'b0111 :
						4'b1111;
		end
	 end
	 
	 // ??? need to make db_in 24 bits to accommodate switches?
	 assign db_in =
		 ~rom_n ? rom_out :
		 ~ram0_n ? ram_out :
		 ~pframrd_n ? pf_out[7:0] :
		 ~ea_read_n ? earom_out :
		 ~in0_n ? playerin_out :
		 ~in1_n ? joystick_out :
		 ~swrd_n ? switch_out :
		 ~pokey_n ? pokey_out :
		 8'b0;
	 
	// EAROM (top 3 high scores)
	reg [5:0]   earom_addr;
	wire [7:0]  earom_out;
	reg [7:0]   earom_in;
	reg [3:0]   earom_ctrl;

	wire ea_addr_clk = !ea_addr_n && !write2_n;
	wire ea_ctrl_clk = !ea_ctrl_n && !write2_n;
	reg ea_addr_clk_last;
	reg ea_ctrl_clk_last;
	wire [3:0] earom_ctrl_in = {db_out[3:2], ~db_out[1], db_out[0] };
	always @(posedge clk_12mhz)
	begin
		if(reset)
		begin
			earom_ctrl <= 4'b0010;
		end
		else
		begin
			if(s_6mhz)
			begin
				ea_addr_clk_last <= ea_addr_clk;
				ea_ctrl_clk_last <= ea_ctrl_clk;

				if(ea_addr_clk && !ea_addr_clk_last)
				begin
					// $display("ea_addr_n > ab=%x", ab[5:0]);
					earom_addr <= ab[5:0];
					earom_in <= db_out;
				end

				if(ea_ctrl_clk && !ea_ctrl_clk_last)
				begin
					// $display("ea_ctrl_n > db_out=%x earom_ctrl_in=%b", db_out, earom_ctrl_in);
					earom_ctrl <= earom_ctrl_in;
					// if(earom_ctrl_in[3:1] == 3'b100) $display("ea_write");
					// if(earom_ctrl_in[3:0] == 4'b1011) $display("ea_read: %x", earom_out);
					// if(earom_ctrl_in[3:1] == 3'b110) $display("ea_erase");
				end
			end
		end
	end
	
	dpram #(6,8) hs_ram 
	(
		.clock_a(clk_12mhz),
		.address_a(earom_addr),
		.data_a(earom_ctrl[2] == 1'b0 ? earom_in : 8'h00),
		.q_a(earom_out),
		.enable_a(s_6mhz && earom_ctrl[3]), // cs1
		.wren_a(~earom_ctrl[1]), // c1

		.clock_b(clk_12mhz),
		.enable_b(1'b1),
		.address_b(hs_address[5:0]),
		.data_b(hs_data_in),
		.q_b(hs_data_out),
		.wren_b(hs_write)
	);

	 // Joystick Circuitry
	 wire js1_right, js1_left, js1_down, js1_up;
	 wire js2_right, js2_left, js2_down, js2_up;

	 assign js1_right = joystick_i[7];
	 assign js1_left = joystick_i[6];
	 assign js1_down = joystick_i[5];
	 assign js1_up = joystick_i[4];
	 assign js2_right = joystick_i[3];
	 assign js2_left = joystick_i[2];
	 assign js2_down = joystick_i[1];
	 assign js2_up = joystick_i[0];

	 wire [7:0] joystick_out_centi = ab[0] ?
			 { js1_right, js1_left, js1_down, js1_up, js2_right, js2_left, js2_down, js2_up } :
			 { dir2, 3'b0, trb };
			 
	 wire [7:0] joystick_out_milli = {
      ab[0] ? { self_test, 1'b0, cocktail, 1'b1 } : { coin_r, coin_l, coin_c, slam },
      cntrlsel ? { js2_down, js2_up, js2_right, js2_left } : { js1_up, js1_down, js1_left, js1_right } };

    assign joystick_out = milli ? joystick_out_milli : joystick_out_centi;
	 
	 // Option Input Circuitry
	 
	 assign switch_out = ab[0] ?
					 sw2_i :
					 sw1_i;

	 // Player Input Circuitry
	 
   wire coin_r, coin_c, coin_l, self_test;
   wire cocktail, slam, start1, start2, fire2, fire1;

   assign coin_r = coin_ctr_r_drive ? coin_ctr_r_drive : playerinput_i[9];
   assign coin_c = coin_ctr_c_drive ? coin_ctr_c_drive : playerinput_i[8];
   assign coin_l = coin_ctr_l_drive ? coin_ctr_l_drive : playerinput_i[7];
   assign self_test = playerinput_i[6];
   assign cocktail = playerinput_i[5];
   assign slam = playerinput_i[4];
   assign start2 = playerinput_i[3];
   assign start1 = playerinput_i[2];
   assign fire2 = playerinput_i[1];
   assign fire1 = playerinput_i[0];

   wire [7:0] playerin_out0;
   wire [7:0] playerin_out1;

   assign playerin_out1 = milli ? 
      { dir2, 1'b0, start2, fire2, sw1_i[7:4] } :
      { coin_r, coin_c, coin_l, slam, fire2, fire1, start2, start1 };

   assign playerin_out0 = milli ?
      { dir1, vblank, start1, fire1, sw1_i[3:0] } :
      { dir1, vblank, self_test, cocktail, tra };

   assign playerin_out = ab[0] ? playerin_out1 : playerin_out0;
	 
	 
	 // Coin Counter Output
	 
	 reg [7:0] cc_latch;

	 always @(posedge s_6mhz or posedge reset) // Mist is 'posedge s_12mhz'
		 if (reset)
			 cc_latch <= 0;
		 else
			 if (~out0_n)
				cc_latch[ ab[2:0] ] <= db_out[7];

   assign flip     = milli ? cc_latch[6] : cc_latch[7];
   assign cntrlsel = milli ? cc_latch[6] : 1'b0;
   assign led_o[4] = milli ? 1'b0 : cc_latch[6];
   assign led_o[3] = milli ? 1'b0 : cc_latch[5];
   assign led_o[2] = cc_latch[4];
   assign led_o[1] = cc_latch[3];
   assign coin_ctr_r_drive = cc_latch[2];
   assign coin_ctr_c_drive = cc_latch[1];
   assign coin_ctr_l_drive = cc_latch[0]; // ??? Mist is cc_latch[1]
	 
	 // Mini-Trak Ball inputs
	 
	 wire [3:0] tb_mux;
	 wire       s_1_horiz_dir, s_1_horiz_ck, s_1_vert_dir, s_1_vert_ck;
	 wire       s_2_horiz_dir, s_2_horiz_ck, s_2_vert_dir, s_2_vert_ck;
	 wire       tb_h_dir, tb_h_ck, tb_v_dir, tb_v_ck;
	 reg 	      tb_h_reg, tb_v_reg;
	 reg [3:0]  tb_h_ctr, tb_v_ctr;
	 wire       tb_h_ctr_clr, tb_v_ctr_clr;
	 
	 assign s_1_horiz_dir = trakball_i[7];
	 assign s_2_horiz_dir = trakball_i[6];
	 assign s_1_horiz_ck  = trakball_i[5];
	 assign s_2_horiz_ck  = trakball_i[4];
	 assign s_1_vert_dir  = trakball_i[3];
	 assign s_2_vert_dir  = trakball_i[2];
	 assign s_1_vert_ck   = trakball_i[1];
	 assign s_2_vert_ck   = trakball_i[0];

	 assign tb_mux = flip ?
			 { s_1_horiz_dir, s_1_horiz_ck, s_1_vert_dir, s_1_vert_ck } :
			 { s_2_horiz_dir, s_2_horiz_ck, s_2_vert_dir, s_2_vert_ck };

	 assign tb_h_dir = tb_mux[3];
	 assign tb_h_ck = tb_mux[2];
	 assign tb_v_dir = tb_mux[1];
	 assign tb_v_ck = tb_mux[0];
	 
	 assign flip_o = flip;
	 
	 /* ??? this was commented out in Mist
	 // H
	 always @(posedge tb_h_ck or posedge reset)
		 if (reset)
			 tb_h_reg <= 0;
		 else
			 tb_h_reg <= tb_h_dir;

	 assign tb_h_ctr_clr = reset | ~steerclr_n;
	 
	 always @(posedge tb_h_ck or posedge tb_h_ctr_clr)
		 if (tb_h_ctr_clr)
			 tb_h_ctr <= 0;
		 else
			 if (tb_h_reg)
	 tb_h_ctr <= tb_h_ctr + 4'd1;
			 else
	 tb_h_ctr <= tb_h_ctr - 4'd1;

	 // V
	 always @(posedge tb_v_ck or posedge reset)
		 if (reset)
			 tb_v_reg <= 0;
		 else
			 tb_v_reg <= tb_v_dir;

	 assign tb_v_ctr_clr = reset | ~steerclr_n;
	 
	 always @(posedge tb_v_ck or posedge tb_v_ctr_clr)
		 if (tb_v_ctr_clr)
			 tb_v_ctr <= 0;
		 else
			 if (tb_v_reg)
	 tb_v_ctr <= tb_v_ctr + 4'd1;
			 else
	 tb_v_ctr <= tb_v_ctr - 4'd1;
	 */

	 assign tra = tb_h_ctr;
	 assign trb = tb_v_ctr;
	 assign dir1 = tb_h_reg;
	 assign dir2 = tb_v_reg;
	 
	 
	 // motion objects (vertical)

	 // the motion object circuitry (vertical) receives pf data and vertical inputs from the
	 // sync generator circuitry to generate the vertical component of the motion object video. PFD8-
	 // 15 from the playfield memory and 1v-128v from the sync generator are compared at F6 and H6.
	 // The output is gated by A7 when a motion object is on one of the sixteen vertical lines and is
	 // latched by E6 and AND gate B7.  A low on B7 pin 8 indicates the presence of a motion object on
	 // one of the vertical lines during non-active video time.  The signal (MATCH) enables the multi-
	 // plexers in the picture data circuitry.
	 //
	 // when 256h goes high, 1v,2v,4v and pic0 are selected. When 256h goes low,
	 // the latched output of E6 is selected. The output if D7 is EXCLUSIVE OR gated at E7 and is
	 // sent to the picture data selector circuitry as motion graphics address (MGA0-MGA3). The other
	 // input to EXCLUSIVE OR gate E7 is PIC7 from the playfield code multiplexer circuitry. PIC7
	 // when high causes the output of E7 to be complimented.  For example, if MGA0..3 are low,
	 // pic7 causes MGA0..3 to go high.  This causes the motion object video to be inverted top
	 // to bottom.

	 // mga0..3 (motion graphics address) from the motion object circuitry,
	 //  256h and 256h_n from the sync generator
	 // pic0..5 represents the code for the object to be displayed
	 // mga0..3 set on of 8 different combinations of the 8-line by
	 //  8-bit blocks of picture video or the 16 line by 8 bit blocks of
	 //  motion object video
	 //
	 // 256h when high selects the playfield picture color codes to be addressed.
	 // 256h when low selects the motion object color codes to be addressed

	 assign match_line = { s_128v, s_64v, s_32v, s_16v, s_8v, s_4v, s_2v, s_1v };
	 assign match_sum = match_line + pfd[15:8];
	 assign match_sum_top = ~(match_sum[7] & match_sum[6] & match_sum[5] & match_sum[4]);

	 always @(negedge s_6mhz)
		if (reset)
			 match_sum_hold <= 0;
		 else
			 if (h_counter[3:1] == 3'b011)	// clock enable rising edge of s_4h
			 match_sum_hold <= { match_sum_top, 1'b0, match_sum[3:0] };

	 assign match_mux = s_256h ? { pic[0], s_4v, s_2v, s_1v } : match_sum_hold[3:0];

	 assign match_n = match_sum_hold[5] & s_256h_n;
	 
	 wire pic7 = milli ? !s_256h & pic[7] : pic[7];
	 
	 // Mister version
	 assign mga = { match_mux[3] ^ (pic[7] & s_256h_n),
		  match_mux[2] ^ pic[7],
		  match_mux[1] ^ pic[7],
		  match_mux[0] ^ pic[7] };
		  
	 // Mist version
	 //assign mga = { match_mux[3] ^ (pic7 & s_256h_n),
		//  match_mux[2] ^ pic7,
		//  match_mux[1] ^ pic7,
		//  match_mux[0] ^ pic7 };

    wire horrot = milli ? (!s_256h & pic[6]) : pic[6];
    wire mga10 = s_256h ? pic[6] : pic[0];
	 
	 
	 // motion objects (horizontal)

	 // the motion object circuitry (horizontal) receives playfield data and horizontal inputs from
	 // the sync generator circuitry. pfd16..23 from the pf memory determine the horizontal
	 // position of the motion object.  pfd24..29 from the pf memory determine the indirect
	 // color of the motion object.   pfd16:23 are latched and loaded into the horizontal position
	 // counter.

//brad
//    always @(posedge s_4h)
//     if (reset)
//       pfd_hold <= 0;
//     else
//       pfd_hold <= pfd[29:16];

		always @(negedge s_6mhz) // ??? mist uses posedge s_12mhz
		if (reset)
			 pfd_hold <= 0;
		 else
			 /* posedge s_4h,  ??? mist says if (s_4h_en) */
			 if (h_counter[3:1] == 3'b011)	// clock enable rising edge of s_4h
				pfd_hold <= pfd[29:16]; // ??? mist uses pfd[31:16]

//   always @(posedge s_4h_n)
//     if (reset)
//       pfd_hold2 <= 0;
//     else
//       pfd_hold2 <= pfd_hold;

	 always @(negedge s_6mhz) // ??? mist uses posedge s_12mhz
		 if (reset)
			 pfd_hold2 <= 0;
		 else
			 /* posedge s_4h_n, ??? mist says if (s_4h_n_en) */
			 if (h_counter[3:1] == 3'b000)	// clock enable rising edge os s_4h_n
		 pfd_hold2 <= pfd_hold;
	 
	 assign y[1] = // C7
		(area == 2'b00) ? (s_256hd ? 1'b0 : gry[1]) :
		(area == 2'b01) ? (s_256hd ? 1'b0 : pfd_hold2[25]) : 
		(area == 2'b10) ? (s_256hd ? 1'b0 : pfd_hold2[27]) :
		(area == 2'b11) ? (s_256hd ? 1'b0 : pfd_hold2[29]) :
		1'b0;

	 assign y[0] = // C7
		(area == 2'b00) ? (s_256hd ? 1'b0 : gry[0]) :
		(area == 2'b01) ? (s_256hd ? 1'b0 : pfd_hold2[24]) : 
		(area == 2'b10) ? (s_256hd ? 1'b0 : pfd_hold2[26]) :
		(area == 2'b11) ? (s_256hd ? 1'b0 : pfd_hold2[28]) :
		1'b0;
		
	 assign mocbx[0] = (area == 2'b00) ? (s_256hd ? 1'b0 : mocb[0]) : pfd_hold2[30];
    assign mocbx[1] = (area == 2'b00) ? (s_256hd ? 1'b0 : mocb[1]) : pfd_hold2[31];

	 assign line_ram_ctr_load = ~(pload_n | s_256h);
	 assign line_ram_ctr_clr = ~(pload_n | ~(s_256h & s_256hd_n));
	 
	 always @(posedge s_6mhz) // ??? Mist uses s_12mhz here
		 if (reset)
			 line_ram_ctr <= 0;
		 else // ??? Mist adds 'if (s_6mhz_en)'
			begin
				if (line_ram_ctr_clr)
					line_ram_ctr <= 0;
				else
					if (line_ram_ctr_load) 
						line_ram_ctr <= pfd_hold[23:16];
					else
						line_ram_ctr <= line_ram_ctr + 8'b1;
			end              
	 
	 assign line_ram_addr = line_ram_ctr;
	 
	 // Mister version
	 always @(posedge s_6mhz)
	   line_ram[line_ram_addr] <= y;
	 
	 // Mist version
	 //always @(posedge s_12mhz)
    // if (~s_6mhz) line_ram[line_ram_addr] <= {mocbx, y};

	 // Mister version
	 always @(posedge s_12mhz)
	 	 if (reset)
	 		 mr <= 0;
	 	 else
	 		 mr <= line_ram[line_ram_addr];
			
	 // Mist version	
	 //always @(negedge s_12mhz)
    // if (reset) begin
    //   mr <= 0;
    //   mocb_o <= 0;
    // end else
    //   {mocb_o, mr} <= line_ram[line_ram_addr];
		 
	 reg  [1:0] mocb, mocb_o;
    wire [1:0] mocbx;
	 
	 // Mister version
	 always @(posedge s_6mhz_n)
		 if (reset)
			 gry <= 0;
		 else
			 if (~mob_n)
				 gry <= 2'b00;
			 else
				 gry <= mr;
	 
	 // Mist version
	 //always @(posedge s_12mhz, negedge mob_n)
    //  if (~mob_n)
    //     gry <= 2'b00;
    //  else if (s_6mhz_n_en) begin
    //     gry <= mr;
    //     mocb <= mocb_o;
    // end

	 
	 //  playfield multiplexer

	 // The playfield multiplexer receives playfield data from the pf memory
	 // (PFD0-PFD31) and the output (pf0..7) is a code that determines what is 1) dis-
	 // played on the monitor or 2) read or updated by the MPU.
	 //
	 // When 256H is low and 4H is high, AB4 and AB5 from the MPU address bus is the
	 // select output from P6.   The output is applied to multiplexers k6, l6, m6 and n6
	 // as select inputs.  When the MPU is accessing the playfield code multiplexer, the
	 // playfield data is either being read or updated by the MPU.  When 256H is high and 4H
	 // is low, the inputs frmo the sync generator (128H and 8V) are the selected outputs.
	 // These signals then select which bits of the data PFD0-PFD31 are send out via K6, L6
	 // M6, and N6 for the playfield codes that eventually are displayed on the monitor.

	//   always @(posedge s_4h)
	//     if (reset)
	//       pic <= 0;
	//     else
	//       pic <= pf[7:0];

	 always @(negedge s_6mhz)
		 if (reset)
			 pic <= 0;
		 else
			if (h_counter[3:1] == 3'b011)		// clock enable rising edge of s_4h
	        pic <= pf[7:0];
			  else if (s_4h_n_en) // from mist
         picD <= pic;          // from mist

			
		
	// ??? this interface is very different from mist version
	dpram #(11) pf_rom1 // HJ7
	(
				.clock_a(clk_12mhz),
				.enable_a(1'b1),
				.wren_a(dn_wr && prog_pf_rom_1_cs),
				.address_a(dn_addr[10:0]),
				.data_a(dn_data),
				.q_a(),

				.clock_b(clk_12mhz),
				.enable_b(s_6mhz_n),
				.address_b(pf_rom1_addr),
				.wren_b(),
				.data_b(),
				.q_b(pf_rom1_out_raw)
	 );

	// ??? this interface is very different from mist version
	dpram #(11) pf_rom0  // F7
	(
				.clock_a(clk_12mhz),
				.enable_a(1'b1),
				.wren_a(dn_wr && prog_pf_rom_0_cs),
				.address_a(dn_addr[10:0]),
				.data_a(dn_data),
				.q_a(),

				.clock_b(clk_12mhz),
				.enable_b(s_6mhz_n),
				.address_b(pf_rom0_addr),
				.wren_b(),
				.data_b(),
				.q_b(pf_rom0_out_raw)
	 );
			
			
	 // a guess, based on millipede schematics
	 wire pf_romx_haddr;
	 assign pf_romx_haddr = milli ? mga10 : s_256h_n & pic[0];

	 assign pf_rom1_addr = { pf_romx_haddr, s_256h, pic[5:1], mga };
	 assign pf_rom0_addr = { pf_romx_haddr, s_256h, pic[5:1], mga };


	 assign pf_rom0_out = reset ? 8'b0 : pf_rom0_out_raw;
	 assign pf_rom1_out = reset ? 8'b0 : pf_rom1_out_raw;

	 assign pf_rom0_out_rev = { pf_rom0_out[0], pf_rom0_out[1], pf_rom0_out[2], pf_rom0_out[3],
						pf_rom0_out[4], pf_rom0_out[5], pf_rom0_out[6], pf_rom0_out[7] };
	 
	 assign pf_rom1_out_rev = { pf_rom1_out[0], pf_rom1_out[1], pf_rom1_out[2], pf_rom1_out[3],
						pf_rom1_out[4], pf_rom1_out[5], pf_rom1_out[6], pf_rom1_out[7] };
	 
	 assign pf_mux0 = match_n ? 8'b0 : (horrot ? pf_rom0_out_rev : pf_rom0_out);
	 assign pf_mux1 = match_n ? 8'b0 : (horrot ? pf_rom1_out_rev : pf_rom1_out);
	 
	 // ??? Mist uses 12mhz here
	 always @(posedge s_6mhz)
		 if (reset)
			 pf_shift1 <= 0;
		 else
			 if (~pload_n)
				pf_shift1 <= pf_mux1;
			 else
				pf_shift1 <= { pf_shift1[6:0], 1'b0 };
	 
	 always @(posedge s_6mhz)
		 if (reset)
			 pf_shift0 <= 0;
		 else
			 if (~pload_n)
	 pf_shift0 <= pf_mux0;
			 else
	 pf_shift0 <= { pf_shift0[6:0], 1'b0 };
	 
	 always @(posedge s_6mhz_n)
		 if (reset)
			 area <= 0;
		 else
			 area <= { pf_shift1[7], pf_shift0[7] };

	 // we ignore the cpu, as pf ram is now dp and cpu has it's own port
	 assign pf_sel = pf_addr_stamp ? 2'b00 : { s_8v, s_128h };
	 
	 assign pf =
				(pf_sel == 2'b00) ? pfd[7:0] :
				(pf_sel == 2'b01) ? pfd[15:8] :
				(pf_sel == 2'b10) ? pfd[23:16] :
				(pf_sel == 2'b11) ? pfd[31:24] :
				8'b0;

	 // playfield address selector

	 // when s_4h_n is low the pf addr selector receives 8h, 16, 32h & 64h and
	 //  16v, 32v, 64v and 128v from the sync generator. these signals enable the sync
	 //  generator circuits to access the playfield memory
	 //
	 // when s_4h_n goes high the game mpu addresses the pf memory
	 // during horizontal blanking pfa4..7 are held high enabling the motion object
	 // circuitry to access the playfield memory for the motion objects to be displayed

	 // ??? mist is assign pf_addr_stamp = hblank & ~s_256h;
	 assign pf_addr_stamp = s_256h_n & s_4h_n;

	 // force pf address to "stamp area" during hblank
	 assign pfa7654 = pf_addr_stamp ? 4'b1111 : { s_128v, s_64v, s_32v, s_16v };
	 assign pfa3210 = { s_64h, s_32h, s_16h, s_8h };
	 assign pfa = { pfa7654, pfa3210 };

	 wire pf_ce;
	 reg 	pf_ce_d;
	 wire [3:0] pf_ce4_n;
	 assign pf_ce = ~(s_1h & s_2h & s_4h & s_6mhz);

	 // ??? mist does not have this
	 always @(posedge s_12mhz)
		 if (reset)
			 pf_ce_d <= 0;
		 else
			 pf_ce_d <= pf_ce;
	 
	 //   assign pf_ce4_n = { pf_ce_d, pf_ce_d, pf_ce_d, pf_ce_d };
	 assign pf_ce4_n = 4'b0;

	 //   ??? Mist uses 12mhz here
	 pf_ram_dp pf_ram(
				.clk_a(s_6mhz),
				.clk_b(s_6mhz/*_n*/),
				.reset(reset),
				//
				.addr_a({ab[9:6], ab[3:0]}),
				.din_a(db_out),
				.dout_a(pf_out),
				.ce_a({pfrd3_n, pfrd2_n, pfrd1_n, pfrd0_n}),
				.we_a({pfwr3_n, pfwr2_n, pfwr1_n, pfwr0_n}),
				//
				.addr_b(pfa),
				.dout_b(pfd),
				.ce_b(pf_ce4_n)
				);
	 
 
	 // Video output circuitry

	 // The video output circuit receives motion object, playfield, address and data inputs 
	 //  and produces a video output to be displayed on the game monitor.
	 // when the alternate color bit is active, an alternate shade of blue or green is available   
	 
	 assign comp_sync = hsync_n & vsync_n;

	 wire blank_disp_n;
	 assign blank_disp_n = hblank_n & vblankd_n;

	 // XXX implement alternate shades of blue and green...
	 always @(posedge s_6mhz_n)
		 if (reset)
			 rgbi <= 4'b1111;		// output is inverted
		else if (~blank_disp_n) 
			rgbi <= 4'b1111;
			else     // mist has else if (s_6mhz_n_en)
			 rgbi <= coloram_rgbi;

	 assign coloram_w_n = write_n | coloram_n;

	 wire gry0_or_1;
	 assign gry0_or_1 = gry[1] | gry[0];
		 
//   assign rama_sel = { coloram_n, gry0_or_1 };
//   
//   assign rama = 
//		 (rama_sel == 2'b00) ? { ab[3:0] } :
//		 (rama_sel == 2'b01) ? { ab[3:0] } :
//		 (rama_sel == 2'b10) ? { {gry0_or_1, 1'b1}, area[1:0] } :
//		 (rama_sel == 2'b11) ? { {gry0_or_1, 1'b1}, gry[1:0] } :
//		 4'b0;

//	 assign rama =  gry0_or_1 ?
//			{ {gry0_or_1, 1'b1}, gry[1:0] } :
//			{ {gry0_or_1, 1'b1}, area[1:0] };

   wire [3:0] rama_centi =  gry0_or_1 ?
      { {gry0_or_1, 1'b1}, gry[1:0] } :
      { {gry0_or_1, 1'b1}, area[1:0] };

   wire rama_hi_sel = (gry0_or_1 & s_256h & s_256h2d);
   wire [4:0] rama_milli = {rama_hi_sel, rama_hi_sel ? {mocb, gry} : {picD[7:6], area}};

   wire [4:0] rama = milli ? rama_milli : {1'b0, rama_centi};
	wire [4:0] cram_a = milli ? ab[4:0] : {1'b0, ab[3:0]};

	 
	// ??? Mist uses 12mhz here
	color_ram color_ram(
		 .clk_a(s_6mhz),
		 .clk_b(s_6mhz_n),
		 .reset(reset),
		 .addr_a(cram_a),
		 .dout_a(coloram_out),
		 .din_a(milli ? db_out : {db_out[3:0], db_out[3:0]}),
		 .we_n_a(coloram_w_n),
		 .addr_b(rama),
		 .dout_b(coloram_rgbi)
	);

	// output to the top level
	// bbb_ggg_rrr
   assign rgb_o = milli ? rgb_o_milli : rgb_o_centi;

   wire [8:0] rgb_o_milli = ~{ rgbi[2:0], rgbi[4:3], 1'b1, rgbi[7:5] };
   wire [8:0] rgb_o_centi = 
		  rgbi[3:0] == 4'b0000 ? 9'b111_111_111 :
		  rgbi[3:0] == 4'b0001 ? 9'b111_111_011 :
		  rgbi[3:0] == 4'b0010 ? 9'b111_011_111 :
		  rgbi[3:0] == 4'b0011 ? 9'b111_011_011 :
		  rgbi[3:0] == 4'b0100 ? 9'b011_111_111 :
		  rgbi[3:0] == 4'b0101 ? 9'b011_111_011 :
		  rgbi[3:0] == 4'b0110 ? 9'b011_011_111 :
		  rgbi[3:0] == 4'b0111 ? 9'b011_011_011 :
		  rgbi[3:0] == 4'b1000 ? 9'b111_111_111 :
		  rgbi[3:0] == 4'b1001 ? 9'b111_111_000 :
		  rgbi[3:0] == 4'b1010 ? 9'b111_000_111 :
		  rgbi[3:0] == 4'b1011 ? 9'b111_000_000 :
		  rgbi[3:0] == 4'b1100 ? 9'b000_111_111 :
		  rgbi[3:0] == 4'b1101 ? 9'b000_111_000 :
		  rgbi[3:0] == 4'b1110 ? 9'b000_000_111 :
		  rgbi[3:0] == 4'b1111 ? 9'b000_000_000 :
		  0;

	 assign sync_o = comp_sync;
	 assign hsync_o = hsync;
	 assign vsync_o = vsync;
	 assign hblank_o = hblank;
	 assign vblank_o = vblank; // Mister code
	 //assign vblank_o = vblankd; // Mist code
	 assign clk_6mhz_o = s_6mhz;
	 
	 
	 // Audio output circuitry
	 
	 // ??? mist does not have this
	 reg [7:0]  last_pokey_rd;
	 always @(posedge s_6mhz)
		 if (reset)
			 last_pokey_rd <= 0;
		 else
			 if (~pokey_n)
	 last_pokey_rd <= pokey_out;

   pokey pokey(
      .reset_n(mpu_reset_n), // was ~reset in Mist
      .clk(phi2 && !pause), // was s_12mhz in Mist
      .enable_179(1'b1), // was phi0_en in Mist
      .data_in(db_out[7:0]),
      .data_out(pokey_out),
      .addr(ab[3:0]),
      .wr_en(~rw_n & ~pokey_n), // written as ~(pokey_n | rw_n) in Mist
      .pot_in(milli ? ~sw2_i[7:0] : 8'd0),
      .channel_0_out(pokey_ch0),
      .channel_1_out(pokey_ch1),
      .channel_2_out(pokey_ch2),
      .channel_3_out(pokey_ch3)
   );
	wire [5:0] pokey_audio = pokey_ch0 + pokey_ch1 + pokey_ch2 + pokey_ch3;

   pokey pokey2(
      .reset_n(mpu_reset_n), // was ~reset in Mist
      .clk(phi2 && !pause), // was s_12mhz in Mist
      .enable_179(1'b1), // was phi0_en in Mist
      .data_in(db_out[7:0]),
      .data_out(pokey2_out),
      .addr(ab[3:0]),
      .wr_en(~rw_n & ~pokey2_n), // written as ~(pokey_n | rw_n) in Mist
      .pot_in(milli ? ~sw2_i[7:0] : 8'd0),
      .channel_0_out(pokey2_ch0),
      .channel_1_out(pokey2_ch1),
      .channel_2_out(pokey2_ch2),
      .channel_3_out(pokey2_ch3)
   );
   wire [5:0] pokey2_audio = pokey2_ch0 + pokey2_ch1 + pokey2_ch2 + pokey2_ch3;
   wire [6:0] pokey_mux = pokey_audio + pokey2_audio;

   assign audio = milli ? (pokey_mux[6] ? 6'h3f : pokey_mux[5:0]) : pokey_audio;
	
	assign audio_o = {audio, 2'b0};
	 
endmodule
