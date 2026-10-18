// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %s | FileCheck %s --check-prefix=CORE --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=ltl.
// RUN: circt-verilog --lower-llhd-formal-to-core %s | FileCheck %s --check-prefix=CORE --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=ltl.
// RUN: circt-verilog --ir-llhd %s -o %t.llhd.mlir
// RUN: FileCheck %s --check-prefix=SIM < %t.llhd.mlir
// RUN: circt-opt %t.llhd.mlir --lower-llhd-formal-to-core | FileCheck %s --check-prefix=CORE --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=ltl.
// RUN: circt-verilog --ir-hw %s | circt-opt --lower-llhd-formal-to-core | FileCheck %s --check-prefix=CORE --implicit-check-not=sim. --implicit-check-not=llhd. --implicit-check-not=ltl.
// REQUIRES: slang

// Warning diagnostics have no formal effect, including when used as an
// immediate assertion action. Unused message formatting must disappear too.
// CORE-LABEL: hw.module @standalone(
// CORE-NEXT: hw.output
// SIM-LABEL: hw.module @standalone(
// SIM: sim.proc.print {{%.+}} {sim.warning}
module standalone(input logic clk, enable, ok, input logic [7:0] value);
  initial $warning("Startup warning");
  always @(posedge clk) begin
    if (enable) $warning("Warning: value=%0d", value);
    assert (ok) else $warning("Assertion warning");
  end
  always_comb
    if (!ok) $warning;
endmodule

// Dropping warnings must preserve other effects in the surrounding process.
// CORE-LABEL: hw.module @state_update(
// CORE: seq.firreg %value
// CORE: hw.output
module state_update(input logic clk, input logic [7:0] value,
                    output logic [7:0] q);
  always @(posedge clk) begin
    $warning("Updating q to %0d", value);
    q <= value;
  end
endmodule

// Concurrent assertions keep their property and clock even with warning actions.
// CORE-LABEL: hw.module @sva_warning(
// CORE-NEXT: verif.clocked_assert %ok if %enable, posedge %clk : i1
// CORE-NEXT: hw.output
module sva_warning(input logic clk, enable, ok);
  assert property (@(posedge clk) enable |-> ok)
    else $warning("Assertion warning");
endmodule

// CORE-LABEL: hw.module @sva_warning_delayed(
// CORE-NEXT: [[CLK:%.+]] = seq.to_clock %clk
// CORE-NEXT: [[PENDING:%.+]] = seq.firreg %enable clock [[CLK]] preset 0 : i1
// CORE-NEXT: verif.clocked_assert %ok if [[PENDING]], posedge %clk : i1
// CORE-NEXT: hw.output
module sva_warning_delayed(input logic clk, enable, ok,
                          input logic [7:0] value);
  assert property (@(posedge clk) enable |=> ok)
    else $warning("Assertion warning: value=%0d", value);
endmodule
