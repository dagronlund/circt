// RUN: circt-opt %s --export-verilog -o /dev/null | FileCheck %s

// Simulation temporaries use their own type keyword, without a reg/logic prefix.
// CHECK-LABEL: module simulation_types
// CHECK: initial begin
// CHECK: string {{.*}};
// CHECK: real {{.*}};
// CHECK: shortreal {{.*}};
hw.module @simulation_types() {
  sv.initial {
    %str = sv.reg : !hw.inout<!hw.string>
    %real = sv.reg : !hw.inout<f64>
    %shortreal = sv.reg : !hw.inout<f32>
    %literal = sv.constantStr "hello"
    // CHECK: = "hello";
    sv.bpassign %str, %literal : !hw.string
    %read = sv.read_inout %str : !hw.inout<!hw.string>
    sv.verbatim "$display(\22%s\22, {{0}});" (%read) : !hw.string
  }
  hw.output
}
