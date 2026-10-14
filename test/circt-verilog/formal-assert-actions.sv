// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --check-prefix=CORE --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --check-prefix=CORE --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-llhd %s -o %t.llhd.mlir
// RUN: FileCheck %s --check-prefix=SIM < %t.llhd.mlir
// RUN: circt-opt %t.llhd.mlir --lower-llhd-formal-to-core | FileCheck %s --check-prefix=CORE --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=seq.
// RUN: circt-verilog --ir-hw %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --check-prefix=CORE --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=seq.
// REQUIRES: slang

// Both error actions retain a clocked verification failure. The diagnostic
// payload is not hardware, and formatting must not add state or affect gating.
// CORE-LABEL: hw.module @literal(
// CORE-DAG: [[FALSE:%.+]] = hw.constant false
// CORE-DAG: [[TRUE:%.+]] = hw.constant true
// CORE-NEXT: [[NOT_OK:%.+]] = comb.xor %ok, [[TRUE]] : i1
// CORE-NEXT: [[FAIL:%.+]] = comb.and [[NOT_OK]], %enable : i1
// CORE-NEXT: verif.clocked_assert [[FALSE]] if [[FAIL]], posedge %clk : i1
// CORE-NEXT: hw.output
// SIM-LABEL: hw.module @literal(
// SIM: sim.fmt.literal "Error: Assertion failed"
// SIM: sim.proc.print {{%.+}} {verif.assertion_failure}
module literal(input logic clk, enable, ok, input logic [7:0] value);
  always @(posedge clk)
    if (enable) assert (ok) else $error("Assertion failed");
endmodule

// CORE-LABEL: hw.module @formatted(
// CORE-DAG: [[FALSE:%.+]] = hw.constant false
// CORE-DAG: [[TRUE:%.+]] = hw.constant true
// CORE-NEXT: [[NOT_OK:%.+]] = comb.xor %ok, [[TRUE]] : i1
// CORE-NEXT: [[FAIL:%.+]] = comb.and [[NOT_OK]], %enable : i1
// CORE-NEXT: verif.clocked_assert [[FALSE]] if [[FAIL]], posedge %clk : i1
// CORE-NEXT: hw.output
// SIM-LABEL: hw.module @formatted(
// SIM: sim.fmt.literal "Error: Assertion failed: value="
// SIM: sim.fmt.dec {{%.+}} specifierWidth 0 : i8
// SIM: sim.fmt.concat
// SIM: sim.proc.print {{%.+}} {verif.assertion_failure}
module formatted(input logic clk, enable, ok, input logic [7:0] value);
  always @(posedge clk)
    if (enable)
      assert (ok) else $error("Assertion failed: value=%0d", value);
endmodule

// Concurrent assertions already carry a verification property. An explicit
// failure message must preserve the property and its sampling clock.
// CORE-LABEL: hw.module @sva_literal(
// CORE-NEXT: verif.clocked_assert %ok if %enable, posedge %clk : i1
// CORE-NEXT: hw.output
// SIM-LABEL: hw.module @sva_literal(
// SIM: [[PROPERTY:%.+]] = ltl.implication %enable, %ok : i1, i1
// SIM: verif.clocked_assert [[PROPERTY]], posedge %clk : !ltl.property
module sva_literal(input logic clk, enable, ok, input logic [7:0] value);
  assert property (@(posedge clk) enable |-> ok)
    else $error("Assertion failed");
endmodule

// CORE-LABEL: hw.module @sva_formatted(
// CORE-NEXT: verif.clocked_assert %ok if %enable, posedge %clk : i1
// CORE-NEXT: hw.output
// SIM-LABEL: hw.module @sva_formatted(
// SIM: [[PROPERTY:%.+]] = ltl.implication %enable, %ok : i1, i1
// SIM: verif.clocked_assert [[PROPERTY]], posedge %clk : !ltl.property
module sva_formatted(input logic clk, enable, ok, input logic [7:0] value);
  assert property (@(posedge clk) enable |-> ok)
    else $error("Assertion failed: value=%0d", value);
endmodule
