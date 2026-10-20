// REQUIRES: slang, libz3, circt-bmc-jit
// RUN: split-file %s %t
// RUN: circt-verilog --ir-hw --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-conditional-array-loop.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core --hw-flatten-modules --hw-aggregate-to-comb --canonicalize --cse -o %t.formal.mlir
// RUN: circt-bmc %t.formal.mlir --module=checks -b 1 --shared-libs=%libz3 | FileCheck %s
// RUN: circt-verilog --ir-llhd --top=checks %CIRCT_SOURCE%/test/circt-verilog/formal-conditional-array-loop.sv %t/checks.sv | circt-opt --lower-llhd-formal-to-core --hw-flatten-modules --hw-aggregate-to-comb --canonicalize --cse -o %t.direct.mlir
// RUN: circt-bmc %t.direct.mlir --module=checks -b 1 --shared-libs=%libz3 | FileCheck %s
// CHECK: Bound reached with no violations!

// Prove the complete output against a whole-array selection for every input
// combination, through both frontend pipelines.
//--- checks.sv
module checks(input logic select_a, input logic [15:0] a, b);
  logic [15:0] q;
  top dut(.select_a, .a, .b, .q);
  always_comb assert(q == (select_a ? a : b));
endmodule
