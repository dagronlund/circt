// RUN: split-file %s %t
// RUN: circt-verilog --ir-hw %t/constant.sv | FileCheck %s --check-prefix=CONSTANT --implicit-check-not=llhd.
// RUN: circt-verilog --ir-hw %t/dynamic.sv | FileCheck %s --check-prefix=DYNAMIC
// REQUIRES: slang
// CONSTANT-LABEL: hw.module @initialization
// CONSTANT: seq.firreg {{.*}} preset 1 : i1
// CONSTANT: seq.firreg
// CONSTANT-NOT: preset
// CONSTANT: hw.output
// DYNAMIC-LABEL: hw.module @dynamic
// DYNAMIC: llhd.sig %d {llhd.explicit_init} : i1
// DYNAMIC: hw.output
//--- constant.sv
module initialization(input bit clk, input bit d, output bit q, output bit r);
  bit state = 1'b1;
  assign q = state;
  always @(posedge clk) begin
    state <= d;
    r <= state;
  end
endmodule

//--- dynamic.sv
module dynamic(input bit clk, input bit d, output bit q);
  bit state = d;
  assign q = state;
  always @(posedge clk) state <= d;
endmodule
