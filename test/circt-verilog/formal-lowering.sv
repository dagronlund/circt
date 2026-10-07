// RUN: split-file %s %t
// RUN: circt-verilog --ir-hw --lower-llhd-formal-to-core %t/checks.sv | FileCheck %s --check-prefix=CORE --implicit-check-not=llhd. --implicit-check-not=ltl. --implicit-check-not=moore. --implicit-check-not=cf. --implicit-check-not=unrealized_conversion_cast
// RUN: circt-verilog --lower-llhd-formal-to-core %t/checks.sv | FileCheck %s --check-prefix=CORE --implicit-check-not=llhd. --implicit-check-not=ltl. --implicit-check-not=moore. --implicit-check-not=cf. --implicit-check-not=unrealized_conversion_cast
// RUN: circt-verilog --ir-hw %t/checks.sv | FileCheck %s --check-prefix=DEFAULT
// RUN: not circt-verilog --lower-llhd-formal-to-core -E %t/checks.sv 2>&1 | FileCheck %s --check-prefix=MODE
// RUN: not circt-verilog --lower-llhd-formal-to-core --lint-only %t/checks.sv 2>&1 | FileCheck %s --check-prefix=MODE
// RUN: not circt-verilog --lower-llhd-formal-to-core --parse-only %t/checks.sv 2>&1 | FileCheck %s --check-prefix=MODE
// RUN: not circt-verilog --lower-llhd-formal-to-core --import-only %t/checks.sv 2>&1 | FileCheck %s --check-prefix=MODE
// RUN: not circt-verilog --lower-llhd-formal-to-core --ir-moore %t/checks.sv 2>&1 | FileCheck %s --check-prefix=MODE
// RUN: not circt-verilog --lower-llhd-formal-to-core --ir-llhd %t/checks.sv 2>&1 | FileCheck %s --check-prefix=MODE
// RUN: not circt-verilog --lower-llhd-formal-to-core %t/unsupported.sv 2>&1 | FileCheck %s --check-prefix=ERROR
// REQUIRES: slang
// UNSUPPORTED: valgrind

// CORE-LABEL: hw.module @checks
// CORE-DAG: verif.assume
// CORE-DAG: verif.assert
// CORE-DAG: verif.cover
// CORE-DAG: seq.firreg
// CORE-DAG: reset async
// CORE-DAG: verif.clocked_assert
// CORE-DAG: verif.clocked_assume
// CORE-DAG: verif.clocked_cover
// CORE: hw.output
// DEFAULT: llhd.combinational
// DEFAULT: ltl.
// MODE: error: --lower-llhd-formal-to-core requires --ir-hw or default HW output
// ERROR: error:
// ERROR-SAME: unsupported

//--- checks.sv
module checks(input bit clk, input bit rst, input bit g, input bit a,
              input bit b);
  always_comb begin
    if (g) begin
      assume (a);
      assert (a || b);
      cover (b);
    end
  end
  assert property (@(posedge clk) disable iff (rst) a |=> b);
  assume property (@(posedge clk) disable iff (rst) a |=> b);
  cover property (@(posedge clk) disable iff (rst) a ##1 b);
endmodule

//--- unsupported.sv
module unsupported(input bit clk, input bit a, input bit b);
  assert property (@(posedge clk) a until b);
endmodule
