module core #(                             //Don't modify interface
	parameter ADDR_W = 32,
	parameter INST_W = 32,
	parameter DATA_W = 32
)(
	input                   i_clk,
	input                   i_rst_n,
	output [ ADDR_W-1 : 0 ] o_i_addr,
	input  [ INST_W-1 : 0 ] i_i_inst,
	output                  o_d_wen,
	output [ ADDR_W-1 : 0 ] o_d_addr,
	output [ DATA_W-1 : 0 ] o_d_wdata,
	input  [ DATA_W-1 : 0 ] i_d_rdata,
	output [        1 : 0 ] o_status,
	output                  o_status_valid
);

// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
// ---- Add your own wires and registers here if needed ---- //
	// FSM state
	reg [2:0] STATE, STATE_nxt;
	parameter IDLE        = 3'd0;
	parameter INST_FETCH  = 3'd1;
	parameter INST_DECODE = 3'd2;
	parameter DATA_ALU    = 3'd3;
	parameter DATA_WRITE  = 3'd4;
	parameter NEXT_PC     = 3'd5;
	parameter END_PROCESS = 3'd6;

	// Program counter
	reg [ADDR_W-1:0] PC, PC_nxt;

	// Instruction
	wire         [5:0] opcode;
	wire         [4:0] s1, s2, s3;
	wire signed [15:0] im;
	
	wire  [1:0] type;
	parameter R   = 2'd0;
	parameter I   = 2'd1;
	parameter EOF = 2'd2;

	// ALU
	wire [DATA_W-1:0] ALU_in_A, ALU_in_B, ALU_out;

	ALU alu(
		.opcode(opcode),
        .ALU_in_A(ALU_in_A),
        .ALU_in_B(ALU_in_B),
        .ALU_out(ALU_out)
	);

	// Register file
	wire              regWrite;              
    wire        [4:0] rs1, rs2, rd;              
    wire [DATA_W-1:0] rs1_data;              
    wire [DATA_W-1:0] rs2_data;              
    reg  [DATA_W-1:0] rd_data; 

	reg_file register(     
		.clk(i_clk),     
		.rst_n(i_rst_n), 
		.wen(regWrite),
		.a1(rs1),      
		.a2(rs2),      
		.aw(rd),       
		.d(rd_data),   
		.q1(rs1_data), 
		.q2(rs2_data)
	);

	// Output status
	reg [1:0] status;
	reg       valid; 
	reg       overflow;

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
// ---- Add your own wire data assignments here if needed ---- //
	assign o_i_addr       = PC;
	assign o_d_wen        = (STATE == DATA_WRITE && opcode == 6'd7) ? 1 : 0;
	assign o_d_addr       = ALU_out;
	assign o_d_wdata      = rs2_data;
	assign o_status       = status;
	assign o_status_valid = valid;

	// Instruction decoding
	assign opcode   = i_i_inst[31:26];
	assign s1       = (type == R) ? i_i_inst[15:11] :
				  	  (type == I) ? i_i_inst[20:16] : 5'b0;
	assign s2       = (type != EOF) ? i_i_inst[25:21] : 5'b0;
	assign s3       = (type == R) ? i_i_inst[20:16] : 5'b0;
	assign im       = (type == I) ? i_i_inst[15:0] : 16'b0;
	assign type     = (opcode == 6'd1 || opcode == 6'd2 || opcode == 6'd3 ||
					   opcode == 6'd4 || opcode == 6'd8 || opcode == 6'd9 ||
					   opcode == 6'd10 || opcode == 6'd13) ? R :
					  (opcode == 6'd5 || opcode == 6'd6 || opcode == 6'd7 ||
					   opcode == 6'd11 || opcode == 6'd12) ? I : EOF;

	// ALU input
	assign ALU_in_A = rs1_data;
	assign ALU_in_B = (type == R || opcode == 6'd11 || opcode == 6'd12) ? rs2_data : {{16{im[15]}}, im};

	// Register file
	assign regWrite = (STATE == DATA_ALU && (opcode == 6'd1 || opcode == 6'd2 || opcode == 6'd3 ||
					   opcode == 6'd4 || opcode == 6'd5 || opcode == 6'd6 ||
					   opcode == 6'd8 || opcode == 6'd9 || opcode == 6'd10 ||
					   opcode == 6'd13)) ? 1 : 0;
	assign rs1      = (opcode == 6'd11 || opcode == 6'd12) ? s1 : s2;
	assign rs2      = (opcode == 6'd7) ? s1 : (opcode == 6'd11 || opcode == 6'd12) ? s2 : s3;
	assign rd       = s1;

	always @(*) begin
		rd_data = (opcode == 6'd6) ? i_d_rdata : ALU_out;
	end

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your conbinational block design here ---- //

	// State control
	always @(*) begin
		case (STATE)
			IDLE       : STATE_nxt = INST_FETCH; 
			INST_FETCH : STATE_nxt = INST_DECODE;
			INST_DECODE: STATE_nxt = (type == EOF) ? END_PROCESS : DATA_ALU;
			DATA_ALU   : STATE_nxt = (overflow == 1) ? END_PROCESS : 
									 (opcode == 6'd7) ? DATA_WRITE : NEXT_PC;
			DATA_WRITE : STATE_nxt = NEXT_PC;
			NEXT_PC    : STATE_nxt = INST_FETCH;
			END_PROCESS: STATE_nxt = IDLE;
			default    : STATE_nxt = IDLE;
		endcase
	end

	// Program Counter
	always @(*) begin
		case (STATE)
			NEXT_PC:
				case (opcode)
					6'd11: // Branch on equal
						PC_nxt = (ALU_out) ? PC + 4 + im : PC + 4;
					6'd12: // Branch on not equal
						PC_nxt = (ALU_out) ? PC + 4 : PC + 4 + im;
					default: 
						PC_nxt = PC + 4;
				endcase
			default:
				PC_nxt = PC;
		endcase
	end
	
	// Overflow check
	always @(*) begin
		case (STATE)
			DATA_ALU:
			 	case (opcode)
					6'd1: // Add
						overflow = ((ALU_in_A[DATA_W-1] & ALU_in_B[DATA_W-1] & ~ALU_out[DATA_W-1]) || (~ALU_in_A[DATA_W-1] & ~ALU_in_B[DATA_W-1] & ALU_out[DATA_W-1])) ? 1 : 0;
					6'd2: // Subtract
						overflow = ((ALU_in_A[DATA_W-1] & ~ALU_in_B[DATA_W-1] & ~ALU_out[DATA_W-1]) || (~ALU_in_A[DATA_W-1] & ALU_in_B[DATA_W-1] & ALU_out[DATA_W-1])) ? 1 : 0;
					6'd3: // Add unsigned
						overflow = (ALU_in_A > ALU_out) ? 1 : 0;
					6'd4: // Subtract unsigned
						overflow = (ALU_in_A < ALU_out) ? 1 : 0;
					6'd5: // Add immediate
						overflow = ((ALU_in_A[DATA_W-1] & ALU_in_B[DATA_W-1] & ~ALU_out[DATA_W-1]) || (~ALU_in_A[DATA_W-1] & ~ALU_in_B[DATA_W-1] & ALU_out[DATA_W-1])) ? 1 : 0;
					6'd6: // Load word
						overflow = (ALU_out >= 1024) ? 1 : 0;
					6'd7: // Store word
						overflow = (ALU_out >= 1024) ? 1 : 0;
					6'd11: // Branch on equal
						overflow = (ALU_out >= 1024) ? 1 : 0;
					6'd12: // Branch on not equal
						overflow = (ALU_out >= 1024) ? 1 : 0;
					default: 
						overflow = 0;
				endcase
			default: 
				overflow = overflow;
		endcase
	end

	// Status control
	always @(*) begin
		case (STATE)
			NEXT_PC: 
				case (type)
					R: status = 0;
					I: status = 1;
					default: status = 0;
				endcase
			END_PROCESS:
				status = (overflow == 1) ? 2 : 3;
			default: status = 0;
		endcase
	end

	always @(*) begin
		case (STATE)
			NEXT_PC:     valid = 1;
			END_PROCESS: valid = 1;
			default:     valid = 0;
		endcase
	end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //

	always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            PC    <= 0;
            STATE <= IDLE;
        end
        else begin
            PC    <= PC_nxt;
            STATE <= STATE_nxt;
        end
    end

endmodule

module ALU #(            
	parameter DATA_W = 32
)(
	input             [5:0] opcode,
	input      [DATA_W-1:0] ALU_in_A,
	input      [DATA_W-1:0] ALU_in_B,
	output reg [DATA_W-1:0] ALU_out
);	
	always @(*) begin
		case (opcode)
			6'd1:    ALU_out = ALU_in_A + ALU_in_B;
			6'd2:    ALU_out = ALU_in_A - ALU_in_B;
			6'd3:    ALU_out = $unsigned(ALU_in_A) + $unsigned(ALU_in_B);
			6'd4:    ALU_out = $unsigned(ALU_in_A) - $unsigned(ALU_in_B);
			6'd5:    ALU_out = ALU_in_A + ALU_in_B;
			6'd6:    ALU_out = ALU_in_A + ALU_in_B;
			6'd7:    ALU_out = ALU_in_A + ALU_in_B;
			6'd8:    ALU_out = ALU_in_A & ALU_in_B;
			6'd9:    ALU_out = ALU_in_A | ALU_in_B;
			6'd10:   ALU_out = ~(ALU_in_A | ALU_in_B);
			6'd11:   ALU_out = ALU_in_A == ALU_in_B;
			6'd12:   ALU_out = ALU_in_A == ALU_in_B;
			6'd13:   ALU_out = ($signed(ALU_in_A) < $signed(ALU_in_B)) ? 1 : 0;
			default: ALU_out = 0;
		endcase
	end
endmodule

module reg_file #(    
	parameter ADDR_W   = 5,         
	parameter DATA_W   = 32,
	parameter REG_SIZE = 32
)(	
	input 				clk,
	input 				rst_n,
	input 				wen,
	input  [ADDR_W-1:0] a1,
	input  [ADDR_W-1:0] a2,
	input  [ADDR_W-1:0] aw,
	input  [DATA_W-1:0] d, 
	output [DATA_W-1:0] q1, 
	output [DATA_W-1:0] q2
);
    reg [DATA_W-1:0] mem     [0:REG_SIZE-1];
    reg [DATA_W-1:0] mem_nxt [0:REG_SIZE-1];

    assign q1 = mem[a1];
    assign q2 = mem[a2];

    integer i;

    always @(*) begin
        for(i = 0; i < REG_SIZE; i = i + 1)
            mem_nxt[i] = (wen && (aw == i)) ? d : mem[i];
    end

    always @(posedge clk or negedge rst_n) begin
        for(i = 0; i < REG_SIZE; i = i + 1)
            mem[i] <= (!rst_n) ? 32'h0 : mem_nxt[i];
    end
endmodule