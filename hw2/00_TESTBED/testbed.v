`timescale 1ns/100ps
`define CYCLE       10.0
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   120000
`define RST_DELAY   5

`ifdef p0
    `define Inst "../00_TESTBED/PATTERN/p0/inst.dat"
    `define Data "../00_TESTBED/PATTERN/p0/data.dat"
	`define Stat "../00_TESTBED/PATTERN/p0/status.dat"
`elsif p1
    `define Inst "../00_TESTBED/PATTERN/p1/inst.dat"
    `define Data "../00_TESTBED/PATTERN/p1/data.dat"
	`define Stat "../00_TESTBED/PATTERN/p1/status.dat"
`endif

module testbed;

	wire clk, rst_n;
	wire [ 31 : 0 ] imem_addr;
	wire [ 31 : 0 ] imem_inst;
	wire            dmem_wen;
	wire [ 31 : 0 ] dmem_addr;
	wire [ 31 : 0 ] dmem_wdata;
	wire [ 31 : 0 ] dmem_rdata;
	wire [  1 : 0 ] mips_status;
	wire            mips_status_valid;

	reg [31:0] output_data [0:63];
	reg  [1:0] output_stat [0:1023];
	reg [31:0] golden_data [0:63];
	reg  [1:0] golden_stat [0:1023];

	initial begin
		$readmemb (`Inst, u_inst_mem.mem_r);
		$readmemb (`Data, u_inst_mem.mem_r);
		$readmemb (`Stat, u_inst_mem.mem_r);
	end

	initial begin
        $fsdbDumpfile("hw2_mips.fsdb");
        $fsdbDumpvars(0, "+mda");
    end

	core u_core (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.o_i_addr(imem_addr),
		.i_i_inst(imem_inst),
		.o_d_wen(dmem_wen),
		.o_d_addr(dmem_addr),
		.o_d_wdata(dmem_wdata),
		.i_d_rdata(dmem_rdata),
		.o_status(mips_status),
		.o_status_valid(mips_status_valid)
	);

	inst_mem  u_inst_mem (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.i_addr(imem_addr),
		.o_inst(imem_inst)
	);

	data_mem  u_data_mem (
		.i_clk(clk),
		.i_rst_n(rst_n),
		.i_wen(dmem_wen),
		.i_addr(dmem_addr),
		.i_wdata(dmem_wdata),
		.o_rdata(dmem_rdata)
	);

	Clkgen u_clk (
        .clk(clk),
        .rst_n(rst_n)
    );

	integer i, num_status, err_stat, err_data;

	initial begin
		err_stat = 0;
		err_data = 0;

		// record output status
		for(i = 0; i < 1024; i = i + 1) begin: record
			@(negedge clk)
			if(mips_status_valid) begin
				output_stat[i] = mips_status;
				if(mips_status == 2'd2 || mips_status == 2'd3) disable record;
			end
		end
		num_status = i;

		// test status
		for(i = 0; i < num_status; i = i + 1) begin
			if(golden_stat[i] != output_stat[i]) begin
				$display("Error! Status[%d]: Golden = %b, Yours = %b", i, golden_stat[i], output_stat[i]);
				err_stat = err_stat + 1;
			end
		end
		
		if(err_stat == 0) begin
            $display("----------------------------------------------");
			$display("               Status ALL PASS!               ");
            $display("----------------------------------------------");
		end else begin
			$display("Total status error: %d", err_stat);
		end

		// test data
		for(i = 0; i < 64; i = i + 1) begin
			if(golden_data[i] != u_data_mem.mem_r[i]) begin
				$display("Error! Data[%d]: Golden = %b, Yours = %b", i, golden_data[i], u_data_mem.mem_r[i]);
				err_data = err_data + 1;
			end
		end
		
		if(err_stat == 0) begin
            $display("----------------------------------------------");
			$display("                Data ALL PASS!                ");
            $display("----------------------------------------------");
		end else begin
			$display("Total data error: %d", err_data);
		end
		$finish;
	end
	
endmodule

module Clkgen (
    output reg clk,
    output reg rst_n
);
    always # (`HCYCLE) clk = ~clk;

    initial begin
        clk = 1'b1;
        rst_n = 1; # (               0.25 * `CYCLE);
        rst_n = 0; # ((`RST_DELAY - 0.25) * `CYCLE);
        rst_n = 1; # (         `MAX_CYCLE * `CYCLE);
        $display("----------------------------------------------");
        $display("Latency of your design is over 120000 cycles!!");
        $display("----------------------------------------------");
        $finish;
    end
endmodule
