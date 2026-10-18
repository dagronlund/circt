// RUN: split-file %s %t
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/standalone.sv 2>&1 | FileCheck %s
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/deferred.sv 2>&1 | FileCheck %s
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/conditional.sv 2>&1 | FileCheck %s
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/warning_text.sv 2>&1 | FileCheck %s
// REQUIRES: slang
// CHECK: error: unsupported operation in strict synchronous formal lowering

// The formal pass may only recover diagnostics identified as assertion failures.
//--- standalone.sv
module top(input logic clk, enable, ok, input logic [7:0] value);
  always @(posedge clk)
    if (enable && !ok) $error("Standalone error: value=%0d", value);
endmodule

// Deferred assertion scheduling is not an immediate synchronous check.
//--- deferred.sv
module top(input logic clk, enable, ok);
  always @(posedge clk)
    if (enable) assert #0 (ok) else $error("Deferred assertion failed");
endmodule

// A diagnostic conditional on another predicate does not identify every
// failure of the enclosing assertion.
//--- conditional.sv
module top(input logic clk, enable, ok, print_enable);
  always @(posedge clk)
    if (enable) assert (ok) else if (print_enable) $error("Assertion failed");
endmodule

// Message text alone must not make an arbitrary print a warning diagnostic.
//--- warning_text.sv
module top(input logic clk);
  always @(posedge clk) $display("Warning: not a warning task");
endmodule
