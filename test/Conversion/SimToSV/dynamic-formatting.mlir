// RUN: circt-opt %s --lower-sim-to-sv | FileCheck %s
// RUN: circt-opt %s --lower-sim-to-sv --export-verilog -o /dev/null | FileCheck %s --check-prefix=SV

// CHECK-LABEL: hw.module @formatting
// SV-LABEL: module formatting
hw.module @formatting() {
  sv.initial {
    // CHECK: sv.reg : !hw.inout<string>
    // SV: string
    %fmt = sim.string.literal "%0d %0d %s %0.2f"
    %n = hw.constant -7 : i32
    %u = hw.constant -1 : i32
    %text = sim.string.literal "%literal"
    %bits = hw.constant 4608308318706860032 : i64
    %real = sv.system "bitstoreal"(%bits) : (i64) -> f64
    // CHECK: sv.system "signed"
    // CHECK: sv.system "unsigned"
    // CHECK: [[CALL:%.*]] = sv.system "sformatf"
    // CHECK: sv.bpassign {{.*}}, [[CALL]] : !hw.string
    // SV: $sformatf("%0d %0d %s %0.2f", $signed({{.*}}), $unsigned({{.*}}),
    // SV: "%literal", $bitstoreal({{.*}}));
    %result = sim.sv.sformat_dynamic %fmt(%n, %u, %text, %real) {isSigned = array<i1: true, false, false, false>} : i32, i32, !sim.dstring, f64
    // Even an unused call must execute, and zero value arguments are supported.
    // CHECK: sv.system "sformatf"
    // CHECK: sv.bpassign
    // SV: = $sformatf("100%%");
    %escape = sim.string.literal "100%%"
    %unused = sim.sv.sformat_dynamic %escape() {isSigned = array<i1>}
  }
  hw.output
}
