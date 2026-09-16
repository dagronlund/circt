// RUN: circt-opt %s --lower-sim-to-sv | FileCheck %s
// RUN: circt-opt %s --lower-sim-to-sv --export-verilog -o /dev/null | FileCheck %s --check-prefix=SV

// Dynamic calls must stay in the containing procedure, and must execute even
// when their return values are unused. In particular, capture the status before
// reading any output temporaries.
// CHECK-LABEL: hw.module @dynamic
// SV-LABEL: module dynamic
hw.module @dynamic() {
  // CHECK: sv.initial {
  // CHECK-NOT: sv.initial
  // SV: initial begin
  sv.initial {
    %name = sim.string.literal "foo"
    %suffix = sim.string.literal "=%d"
    %format = sim.string.concat (%name, %suffix)
    // CHECK: [[FOUND:%.*]] = sv.system "test$plusargs"
    // CHECK: sv.bpassign %{{.*}}, [[FOUND]]
    // SV: = $test$plusargs("foo");
    %found = sim.plusargs.test_dynamic %name
    // CHECK: [[STATUS:%.*]] = sv.system "value$plusargs"(%{{.*}}, %{{.*}})
    // CHECK: sv.bpassign %{{.*}}, [[STATUS]]
    // SV: = $value$plusargs("foo=%d",
    %ok, %value = sim.plusargs.value_dynamic %format : i32
  }
  hw.output
}
