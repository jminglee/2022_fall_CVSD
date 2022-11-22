module alu #(
    parameter INT_W  = 3,
    parameter FRAC_W = 5,
    parameter INST_W = 3,
    parameter DATA_W = INT_W + FRAC_W
)(
    input                     i_clk,
    input                     i_rst_n,
    input                     i_valid,
    input signed [DATA_W-1:0] i_data_a,
    input signed [DATA_W-1:0] i_data_b,
    input        [INST_W-1:0] i_inst,
    output                    o_valid,
    output       [DATA_W-1:0] o_data
);
    
// ---------------------------------------------------------------------------
// Wires and Registers
// ---------------------------------------------------------------------------
reg [DATA_W:0] o_data_w, o_data_r;
reg            o_valid_w, o_valid_r;
// ---- Add your own wires and registers here if needed ---- //
reg [2*DATA_W-1:0] tmp;

reg state;
parameter ALU  = 1'b0;
parameter OUT  = 1'b1;

// ---------------------------------------------------------------------------
// Continuous Assignment
// ---------------------------------------------------------------------------
assign o_valid = o_valid_r;
assign o_data = o_data_r;
// ---- Add your own wire data assignments here if needed ---- //

// ---------------------------------------------------------------------------
// Combinational Blocks
// ---------------------------------------------------------------------------
// ---- Write your combinational block design here ---- //
always@(posedge i_valid) 
begin
    case (i_inst)
        3'b000:  // ADD
        begin
            o_data_w = i_data_a + i_data_b;
            if ( ~i_data_a[DATA_W-1] & ~i_data_b[DATA_W-1] & o_data_w[DATA_W-1]) o_data_w = 8'b01111111; 
            if ( i_data_a[DATA_W-1] & i_data_b[DATA_W-1] & ~o_data_w[DATA_W-1])  o_data_w = 8'b10000000;
            o_valid_w = 1;
        end
        3'b001:  // SUB
        begin
            o_data_w = i_data_a - i_data_b;
            if ( ~i_data_a[DATA_W-1] & i_data_b[DATA_W-1] & o_data_w[DATA_W-1])  o_data_w = 8'b01111111; 
            if ( i_data_a[DATA_W-1] & ~i_data_b[DATA_W-1] & ~o_data_w[DATA_W-1]) o_data_w = 8'b10000000;
            o_valid_w = 1;
        end
        3'b010:  // MUL
        begin
            tmp = i_data_a * i_data_b;
            o_data_w = tmp[12:5] + ((tmp[4]) ? 1 : 0);
            if ( !(i_data_a[DATA_W-1] ^ i_data_b[DATA_W-1]) && tmp[15:13] != 3'b000) o_data_w = 8'b01111111; 
            if ( (i_data_a[DATA_W-1] ^ i_data_b[DATA_W-1]) && tmp[15:13] != 3'b111)  o_data_w = 8'b10000000; 
            o_valid_w = 1;
        end
        3'b011:  // NAND   
        begin
            o_data_w = ~(i_data_a & i_data_b);
            o_valid_w = 1;
        end
        3'b100:  // XNOR
        begin
            o_data_w = ~(i_data_a ^ i_data_b);
            o_valid_w = 1;
        end
        3'b101:  // Sigmoid
        begin
            if (i_data_a >= 8'b01000000 && ~i_data_a[DATA_W-1])     o_data_w = 8'b00100000;
            else if (i_data_a <= 8'b11000000 && i_data_a[DATA_W-1]) o_data_w = 8'b00000000;
            else
            begin
                o_data_w = (i_data_a + 8'b01000000) >> 2;
                o_data_w[7:5] = 3'b000;
            end 
            o_valid_w = 1;
        end
        3'b110:  // Right Circular Shift
        begin
            o_data_w = i_data_a;
            for (tmp = 0; tmp < i_data_b % 8; tmp = tmp + 1) o_data_w = {o_data_w[0],o_data_w[DATA_W-1:1]};
            o_valid_w = 1;
        end
        3'b111:  // MIN
        begin
            o_data_w = (i_data_a < i_data_b) ? i_data_a : i_data_b;
            o_valid_w = 1;
        end
        default: 
        begin
            o_data_w = 0;
            o_valid_w = 0;
        end
    endcase
end

// ---------------------------------------------------------------------------
// Sequential Block
// ---------------------------------------------------------------------------
// ---- Write your sequential block design here ---- //
always@(posedge i_clk or negedge i_rst_n) 
begin
    if(!i_rst_n) 
    begin
        o_data_r  <= 0;
        o_valid_r <= 0;
        state     <= ALU;
    end 
    else 
    case (state)
        ALU:
        begin
            o_data_r  <= 0;
            o_valid_r <= 0;
            state     <= (o_valid_w) ? OUT : ALU;
        end 
        OUT:
        begin
            o_data_r  <= o_data_w;
            o_valid_r <= 1;
            state     <= (i_valid) ? ALU : OUT;
        end
        default:  
        begin
            o_data_r  <= 0;
            o_valid_r <= 0;
            state     <= ALU;
        end 
    endcase
end
endmodule
