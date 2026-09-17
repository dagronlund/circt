// RUN: circt-verilog --ir-llhd %s | FileCheck %s
// REQUIRES: slang

// CHECK-LABEL: hw.module @AssertionControl
module AssertionControl;
  initial begin
    // CHECK: sim.assertion_control true
    $asserton;
    // CHECK-NEXT: sim.assertion_control true
    $asserton();
    // CHECK-NEXT: sim.assertion_control false
    $assertoff;
    // CHECK-NEXT: sim.assertion_control false
    $assertoff();
  end
endmodule
