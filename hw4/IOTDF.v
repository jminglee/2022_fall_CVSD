`timescale 1ns/10ps
module IOTDF(clk, rst, in_en, iot_in, fn_sel, busy, valid, iot_out);
input          clk;
input          rst;
input          in_en;
input    [7:0] iot_in;
input    [2:0] fn_sel;
output         busy;
output         valid;
output [127:0] iot_out;

integer i;

// ********************//
// *****   INPUT  *****//
// ********************//

reg       en;
reg [7:0] data_in;
reg [2:0] DF_mode;

// functional set 
parameter MAX     = 3'b001;
parameter MIN     = 3'b010;
parameter AVG     = 3'b011;
parameter EXTRACT = 3'b100;
parameter EXCLUDE = 3'b101;
parameter PEAKMAX = 3'b110;
parameter PEAKMIN = 3'b111;

parameter low_f4  = 128'h6FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
parameter high_f4 = 128'hAFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
parameter low_f5  = 128'h7FFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
parameter high_f5 = 128'hBFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        en      <= 0;
        data_in <= 0;
        DF_mode <= 0;
    end else begin
        en      <= in_en;
        data_in <= iot_in;
        DF_mode <= fn_sel;
    end
end

// *******************//
// *****   FSM   *****//
// *******************//

reg [1:0] state, state_nxt;
reg [6:0] counter;
reg       round0;
parameter IDLE  = 2'd0;
parameter RESET = 2'd1;
parameter READ  = 2'd2;

// next state
always @(*) begin
    case (state)
        IDLE:    state_nxt = RESET;
        RESET:   state_nxt = READ;
        READ:    state_nxt = READ;
        default: state_nxt = IDLE;
    endcase
end

always @(posedge clk or posedge rst) begin
    if (rst) begin
       state   <= IDLE; 
       counter <= 0;
       round0  <= 0;
    end else begin
       state   <= state_nxt;
       counter <= (en) ? counter + 1 : counter; 
       round0  <= round0 | (counter == 1);
    end
end

// **********************//
// *****   READIN   *****//
// **********************//

reg   [3:0] carry;
reg [130:0] buffer;
wire  [6:0] idx = {counter[3:0],3'b0};

always @(posedge clk or posedge rst) begin
    if (rst)                 buffer <= (DF_mode == PEAKMIN) ? 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF : 0;
    else if (state != READ)  buffer <= (DF_mode == PEAKMIN) ? 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF : 0;
    else if (DF_mode == AVG) buffer <= (counter == 0) ? data_in : buffer + (data_in << idx);
    else begin
        buffer <= buffer;
        buffer[idx +: 8] <= data_in;
    end 
end

// **********************//
// *****   OUTPUT   *****//
// **********************//

assign busy = 0;

reg [127:0] data_out;
assign iot_out = (DF_mode == MAX) ? ((buffer > data_out) ? buffer : data_out) : 
                 (DF_mode == MIN) ? ((buffer < data_out) ? buffer : data_out) : 
                 (DF_mode == AVG) ? buffer[130:3] :  
                 (DF_mode == EXTRACT) ? data_out :  
                 (DF_mode == EXCLUDE) ? data_out : 
                 (DF_mode == PEAKMAX) ? ((~round0 && buffer > data_out) ? buffer : data_out) : 
                 (DF_mode == PEAKMIN) ? ((~round0 && buffer < data_out) ? buffer : data_out) : 0;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        case (DF_mode)
            MIN:     data_out <= 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
            PEAKMIN: data_out <= 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
            default: data_out <= 128'h0;
        endcase
    end else if (state == RESET) begin
        case (DF_mode)
            MIN:     data_out <= 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
            PEAKMIN: data_out <= 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
            default: data_out <= 128'h0;
        endcase
    end else if (counter == 0) begin
        case (DF_mode)
            MIN:     data_out <= 128'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
            EXTRACT: data_out <= buffer;
            EXCLUDE: data_out <= buffer;
            PEAKMAX: data_out <= (buffer > data_out && round0) ? buffer : data_out;
            PEAKMIN: data_out <= (buffer < data_out && round0) ? buffer : data_out;
            default: data_out <= 128'h0;
        endcase    
    end else if (counter[3:0] == 0) begin
        case (DF_mode)
            MAX:     data_out <= (buffer > data_out) ? buffer : data_out;
            MIN:     data_out <= (buffer < data_out) ? buffer : data_out;
            AVG:     data_out <= buffer[130:3];
            EXTRACT: data_out <= buffer;
            EXCLUDE: data_out <= buffer;
            PEAKMAX: data_out <= (buffer > data_out) ? buffer : data_out;
            PEAKMIN: data_out <= (buffer < data_out) ? buffer : data_out;
            default: data_out <= 128'h0;
        endcase    
    end else         data_out <= data_out;
end

reg valid_, peak;
assign valid = valid_;

always @(posedge clk or posedge rst) begin
    if (rst)         valid_ <= 0;
    else begin
        case (DF_mode)
            MAX:     valid_ <= (counter == 127);
            MIN:     valid_ <= (counter == 127);
            AVG:     valid_ <= (counter == 127);
            EXTRACT: valid_ <= (counter[3:0] == 0 && (buffer > low_f4 && buffer < high_f4) && round0);
            EXCLUDE: valid_ <= (counter[3:0] == 0 && (buffer < low_f5 || buffer > high_f5) && round0);
            PEAKMAX: valid_ <= (counter == 1 && peak);
            PEAKMIN: valid_ <= (counter == 1 && peak);
            default: valid_ <= 0;
        endcase 
    end
end

always @(posedge clk or posedge rst) begin
    if (rst)           peak <= 0;
    else if (valid_)   peak <= 0;
    else begin
        case (DF_mode)
            PEAKMAX:   peak <= peak | (counter[3:0] == 0 && buffer > data_out);
            PEAKMIN:   peak <= peak | (counter[3:0] == 0 && buffer < data_out);
            default:   peak <= 0;
        endcase  
    end
end

endmodule