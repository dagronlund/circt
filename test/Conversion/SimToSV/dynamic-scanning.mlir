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
  // CHECK-DAG: sv.reg : !hw.inout<string>
  // CHECK-DAG: sv.reg : !hw.inout<f64>
  // SV: initial begin
  sv.initial {
    %name = sim.string.literal "foo"
    %suffix = sim.string.literal "=%d"
    %format = sim.string.concat (%name, %suffix)
    // CHECK: sv.system "sscanf"
    // SV: = $sscanf("foo", "foo=%d",
    %count, %values:2 = sim.sv.sscanf_dynamic %name, %format : i32, i16
    // CHECK: sv.system "fopen"
    // SV: = $fopen("foo", "=%d");
    %fd = sim.sv.fopen_dynamic %name, %suffix
    // CHECK: sv.system "fscanf"
    // SV: = $fscanf(
    %n, %x = sim.sv.fscanf_dynamic %fd, %format : i32
    // Simulation destinations include strings and reals, not only integers.
    // CHECK: sv.system "sscanf"
    // SV: = $sscanf("foo", "foo=%d",
    %mixedCount, %mixed:2 = sim.sv.sscanf_dynamic %name, %format : !sim.dstring, f64
    // A scan without destinations still has side effects and a return count.
    // CHECK: sv.system "fscanf"
    // SV: = $fscanf(
    %ignored = sim.sv.fscanf_dynamic %fd, %format
  }
  hw.output
}
