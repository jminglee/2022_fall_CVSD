
module core (                       //Don't modify interface
	input         i_clk,
	input         i_rst_n,
	input         i_op_valid,
	input  [ 3:0] i_op_mode,
    output        o_op_ready,
	input         i_in_valid,
	input  [ 7:0] i_in_data,
	output        o_in_ready,
	output        o_out_valid,
	output [12:0] o_out_data
);

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //

	// FSM state
	reg  [1:0] state, state_nxt;
	reg [11:0] counter, counter_nxt, counter_bound;
	parameter IDLE     = 2'd0;
	parameter OPASK    = 2'd1;
	parameter OPREAD   = 2'd2;
	parameter OPERATE  = 2'd3;
 
	reg [3:0] op_mode;
	parameter LOAD_IN = 4'b0000;
	parameter SHIFT_R = 4'b0001;
	parameter SHIFT_L = 4'b0010;
	parameter SHIFT_U = 4'b0011;
	parameter SHIFT_D = 4'b0100;
	parameter SCALE_D = 4'b0101;
	parameter SCALE_U = 4'b0110;
	parameter CONV    = 4'b0111;
	parameter DISPLAY = 4'b1000;

	reg        out_valid;
	reg [12:0] out_data;

	// Convolution 
	reg          [5:0] origin;
	reg          [5:0] depth;
	reg                conv_valid;
	reg         [16:0] conv_result [0:3];
	wire        [11:0] conv_result_idx;    
	wire signed [11:0] conv_shift [0:15];

	// Display
	wire [3:0] display_shift [0:3];

	// SRAM
	reg  [11:0] address;
	reg         cen;
	reg         wen;
	wire  [7:0] sram_data_tmp;
	wire  [7:0] sram_data;

	sram_4096x8 sram(
		.Q(sram_data_tmp),
		.CLK(i_clk),
		.CEN(cen),
		.WEN(wen),
		.A(address),
		.D(i_in_data)
	);

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //

	assign o_op_ready  = (state == OPASK) ? 1 : 0;
	assign o_in_ready  = (op_mode == LOAD_IN) ? 1 : 0;
	assign o_out_valid = out_valid;
	assign o_out_data  = out_data;

	assign sram_data = (conv_valid) ? sram_data_tmp : 0;

	assign conv_result_idx = counter - (depth << 4) - 1;

	assign conv_shift[0]  = -9;
	assign conv_shift[1]  = -8;
	assign conv_shift[2]  = -7;
	assign conv_shift[3]  = -6;
	assign conv_shift[4]  = -1;
	assign conv_shift[5]  = 0;
	assign conv_shift[6]  = 1;
	assign conv_shift[7]  = 2;
	assign conv_shift[8]  = 7;
	assign conv_shift[9]  = 8;
	assign conv_shift[10] = 9;
	assign conv_shift[11] = 10;
	assign conv_shift[12] = 15;
	assign conv_shift[13] = 16;
	assign conv_shift[14] = 17;
	assign conv_shift[15] = 18;

	assign display_shift[0] = 0;
	assign display_shift[1] = 1;
	assign display_shift[2] = 8;
	assign display_shift[3] = 9;

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

	// Next state
	always @(*) begin
		case (state)
			IDLE:    state_nxt = OPASK;
			OPASK:   state_nxt = OPREAD;
			OPREAD:  state_nxt = OPERATE;
			OPERATE: state_nxt = (counter == counter_bound) ? IDLE : OPERATE;
			default: state_nxt = IDLE;
		endcase
	end

	// Counter 
	always @(*) begin
		case (state_nxt)
			OPERATE: counter_nxt = (state == OPREAD) ? 0 : counter + 1;
			default: counter_nxt = 0;
		endcase
	end

	// Counter bound
	always @(*) begin
		case ({state, op_mode})
			{OPERATE, LOAD_IN}: counter_bound = 2048;
			{OPERATE, CONV}:    counter_bound = (depth << 4) + 4;
			{OPERATE, DISPLAY}: counter_bound = (depth << 2);
			default:            counter_bound = 0;
		endcase
	end

	// SRAM: address
	always @(*) begin
		case ({state, op_mode})
			{OPERATE, LOAD_IN}: 
				address = counter;
			{OPERATE, CONV}: 
				address = (counter < (depth << 4)) ? (origin + (counter[11:4] << 6) + conv_shift[counter[3:0]]) : 0;
			{OPERATE, DISPLAY}: 
				address = origin + (counter[11:2] << 6) + display_shift[counter[1:0]];
			default: 
				address = 0;
		endcase
	end

	// SRAM: cen
	always @(*) begin
		case ({state, op_mode})
			{OPERATE, LOAD_IN}: 
				cen = (i_in_valid) ? 0 : 1;
			{OPERATE, CONV}:  
				cen = ((counter >= (depth << 4)) || (origin <  8 && counter[3:0] <  4) ||(origin > 56 && counter[3:0] > 12) ||
					   (origin[2:0] == 0 && counter[1:0] == 0) || (origin[2:0] == 7 && counter[1:0] == 3)) ? 1 : 0;
			{OPERATE, DISPLAY}: 
				cen = 0;
			default:  
 				cen = 1;
		endcase
	end

	// SRAM: wen
	always @(*) begin
		case ({state, op_mode})
			{OPERATE, CONV}: 	wen = 1;
			{OPERATE, DISPLAY}: wen = 1;
			default:            wen = 0;
		endcase
	end

	// SRAM: out_data
	always @(*) begin
		case ({state, op_mode})
			{OPERATE, CONV}:    out_data = conv_result[conv_result_idx][16:4] + conv_result[conv_result_idx][3];
			{OPERATE, DISPLAY}: out_data = {5'b0, sram_data};
			default:            out_data = 0;
		endcase
	end

	// SRAM: out_valid
	always @(*) begin
		case ({state, op_mode})
			{OPERATE, CONV}:    out_valid = (counter <= (depth << 4)) ? 0 : 1;
			{OPERATE, DISPLAY}: out_valid = (counter == 0) ? 0 : 1;
			default:            out_valid = 0; 
		endcase
	end

	// Convolution
	always @(posedge i_clk) begin
		if ({state, op_mode} == {OPERATE, CONV}) begin
			if (counter == 0) begin
				conv_result[0] <= 0;
				conv_result[1] <= 0;
				conv_result[2] <= 0;
				conv_result[3] <= 0;
			end else if (conv_valid) begin
				case (counter[3:0])
					1:       conv_result[0] <= conv_result[0] + {9'b0, sram_data};
					2:       conv_result[0] <= conv_result[0] + {8'b0, sram_data, 1'b0};
					3:       conv_result[0] <= conv_result[0] + {9'b0, sram_data};
					4:       conv_result[0] <= conv_result[0];
					5:       conv_result[0] <= conv_result[0] + {8'b0, sram_data, 1'b0};
					6:       conv_result[0] <= conv_result[0] + {7'b0, sram_data, 2'b0};
					7:       conv_result[0] <= conv_result[0] + {8'b0, sram_data, 1'b0};
					8:       conv_result[0] <= conv_result[0];
					9:       conv_result[0] <= conv_result[0] + {9'b0, sram_data};
					10:      conv_result[0] <= conv_result[0] + {8'b0, sram_data, 1'b0};
					11:      conv_result[0] <= conv_result[0] + {9'b0, sram_data};
					12:      conv_result[0] <= conv_result[0];
					13:      conv_result[0] <= conv_result[0];
					14:      conv_result[0] <= conv_result[0];
					15:      conv_result[0] <= conv_result[0];
					0:       conv_result[0] <= conv_result[0];
					default: conv_result[0] <= conv_result[0];
				endcase
				case (counter[3:0])
					1:       conv_result[1] <= conv_result[1];
					2:       conv_result[1] <= conv_result[1] + {9'b0, sram_data};
					3:       conv_result[1] <= conv_result[1] + {8'b0, sram_data, 1'b0};
					4:       conv_result[1] <= conv_result[1] + {9'b0, sram_data};
					5:       conv_result[1] <= conv_result[1];
					6:       conv_result[1] <= conv_result[1] + {8'b0, sram_data, 1'b0};
					7:       conv_result[1] <= conv_result[1] + {7'b0, sram_data, 2'b0};
					8:       conv_result[1] <= conv_result[1] + {8'b0, sram_data, 1'b0};
					9:       conv_result[1] <= conv_result[1];
					10:      conv_result[1] <= conv_result[1] + {9'b0, sram_data};
					11:      conv_result[1] <= conv_result[1] + {8'b0, sram_data, 1'b0};
					12:      conv_result[1] <= conv_result[1] + {9'b0, sram_data};
					13:      conv_result[1] <= conv_result[1];
					14:      conv_result[1] <= conv_result[1];
					15:      conv_result[1] <= conv_result[1];
					0:       conv_result[1] <= conv_result[1];
					default: conv_result[1] <= conv_result[1];
				endcase
				case (counter[3:0])
					1:       conv_result[2] <= conv_result[2];
					2:       conv_result[2] <= conv_result[2];
					3:       conv_result[2] <= conv_result[2];
					4:       conv_result[2] <= conv_result[2];
					5:       conv_result[2] <= conv_result[2] + {9'b0, sram_data};
					6:       conv_result[2] <= conv_result[2] + {8'b0, sram_data, 1'b0};
					7:       conv_result[2] <= conv_result[2] + {9'b0, sram_data};
					8:       conv_result[2] <= conv_result[2];
					9:       conv_result[2] <= conv_result[2] + {8'b0, sram_data, 1'b0};
					10:      conv_result[2] <= conv_result[2] + {7'b0, sram_data, 2'b0};
					11:      conv_result[2] <= conv_result[2] + {8'b0, sram_data, 1'b0};
					12:      conv_result[2] <= conv_result[2];
					13:      conv_result[2] <= conv_result[2] + {9'b0, sram_data};
					14:      conv_result[2] <= conv_result[2] + {8'b0, sram_data, 1'b0};
					15:      conv_result[2] <= conv_result[2] + {9'b0, sram_data};
					0:       conv_result[2] <= conv_result[2];
					default: conv_result[2] <= conv_result[2];
				endcase
				case (counter[3:0])
					1:       conv_result[3] <= conv_result[3];
					2:       conv_result[3] <= conv_result[3];
					3:       conv_result[3] <= conv_result[3];
					4:       conv_result[3] <= conv_result[3];
					5:       conv_result[3] <= conv_result[3];
					6:       conv_result[3] <= conv_result[3] + {9'b0, sram_data};
					7:       conv_result[3] <= conv_result[3] + {8'b0, sram_data, 1'b0};
					8:       conv_result[3] <= conv_result[3] + {9'b0, sram_data};
					9:       conv_result[3] <= conv_result[3];
					10:      conv_result[3] <= conv_result[3] + {8'b0, sram_data, 1'b0};
					11:      conv_result[3] <= conv_result[3] + {7'b0, sram_data, 2'b0};
					12:      conv_result[3] <= conv_result[3] + {8'b0, sram_data, 1'b0};
					13:      conv_result[3] <= conv_result[3];
					14:      conv_result[3] <= conv_result[3] + {9'b0, sram_data};
					15:      conv_result[3] <= conv_result[3] + {8'b0, sram_data, 1'b0};
					0:       conv_result[3] <= conv_result[3] + {9'b0, sram_data};
					default: conv_result[3] <= conv_result[3];
				endcase
			end else begin
				conv_result[0] <= conv_result[0];
				conv_result[1] <= conv_result[1];
				conv_result[2] <= conv_result[2];
				conv_result[3] <= conv_result[3];
			end
		end else begin
			conv_result[0] <= 0;
			conv_result[1] <= 0;
			conv_result[2] <= 0;
			conv_result[3] <= 0;
		end
	end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //

	always @(posedge i_clk or negedge i_rst_n) begin
		if (!i_rst_n) begin
			state      <= IDLE;
			counter    <= 0;
			conv_valid <= 0;
			op_mode    <= 0;
		end
		else begin
			state      <= state_nxt;
			counter    <= counter_nxt;
			conv_valid <= ~cen;
			op_mode    <= (i_op_valid) ? i_op_mode : op_mode;
		end
	end

	// Origin shift
	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			origin <= 0;
		end else begin
			case ({state, op_mode})
				{OPERATE, SHIFT_R}: origin <= (origin[2:0] == 6) ? origin : origin + 1;
				{OPERATE, SHIFT_L}: origin <= (origin[2:0] == 0) ? origin : origin - 1;
				{OPERATE, SHIFT_U}: origin <= (origin <  8) ? origin : origin - 8;
				{OPERATE, SHIFT_D}: origin <= (origin > 55) ? origin : origin + 8 ;
				default:            origin <= origin;
			endcase	
		end 
		
	end

	// Channel depth
	always @(posedge i_clk or negedge i_rst_n) begin
		if(!i_rst_n) begin
			depth <= 32;
		end else begin
			case ({state, op_mode})
				{OPERATE, SCALE_D}: depth <= (depth ==  8) ? depth : (depth >> 1);
				{OPERATE, SCALE_U}: depth <= (depth == 32) ? depth : (depth << 1);
				default:            depth <= depth;
			endcase	
		end 
		
	end

endmodule
