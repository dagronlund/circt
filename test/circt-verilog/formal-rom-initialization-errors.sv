// RUN: split-file %s %t
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/partial.sv 2>&1 | FileCheck %s --check-prefix=PROCESS
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/runtime.sv 2>&1 | FileCheck %s --check-prefix=PROCESS
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/extra-driver.sv 2>&1 | FileCheck %s --check-prefix=DRIVER
// REQUIRES: slang
// DRIVER: error: signal must have exactly one resolved driver
// PROCESS: error: unsupported formal process

// Unwritten entries must not inherit scheduling zeros as ROM contents.
//--- partial.sv
module top(input logic [1:0] address, output logic [1:0][3:0] q);
  typedef logic [1:0][3:0] word_t;
  word_t rom [0:3];
  initial for (logic [2:0] i = 0; i < 3; i++)
    rom[i] = word_t'(i * i + 1);
  always_comb q = rom[address];
endmodule

// A startup value read from an input must not become a live combinational ROM.
//--- runtime.sv
module top(input logic [1:0] address, input logic [7:0] seed,
           output logic [1:0][3:0] q);
  typedef logic [1:0][3:0] word_t;
  word_t rom [0:3];
  initial for (logic [2:0] i = 0; i < 4; i++)
    rom[i] = word_t'(i * i + seed);
  always_comb q = rom[address];
endmodule

// Constant initialization must not hide an independent driver of the same ROM.
//--- extra-driver.sv
module top(input logic [1:0] address, input logic [1:0][3:0] d,
           output logic [1:0][3:0] q);
  typedef logic [1:0][3:0] word_t;
  word_t rom [0:3];
  initial for (logic [2:0] i = 0; i < 4; i++)
    rom[i] = word_t'(i * i + 1);
  always @(d) rom[0] = d;
  always_comb q = rom[address];
endmodule
