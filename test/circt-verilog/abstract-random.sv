// RUN: circt-verilog --ir-hw %s -o %t.hw.mlir
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued --verif-abstract-random | FileCheck %s --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: circt-opt %t.hw.mlir --verif-abstract-random --comb-assume-two-valued | FileCheck %s --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: circt-opt %t.hw.mlir --comb-assume-two-valued -o %t.two.mlir
// RUN: circt-opt %t.two.mlir --verif-abstract-random | FileCheck %s --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: circt-opt %t.two.mlir --verif-abstract-random='assume-ranges=false' | FileCheck %s --check-prefix=UNBOUNDED --implicit-check-not=verif.assume --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: circt-verilog --ir-llhd %s | circt-opt --comb-assume-two-valued --verif-abstract-random | FileCheck %s --implicit-check-not=__circt_urandom_range --implicit-check-not=llvm.
// RUN: FileCheck %s --check-prefix=DEFAULT --implicit-check-not=verif.symbolic_value < %t.hw.mlir
// REQUIRES: slang

// The three source functions work on ordinary upstream Verilog-to-HW output.
// Full-width random/urandom calls still have no range assumptions.
// CHECK-LABEL: hw.module @draws(
// CHECK-COUNT-2: verif.symbolic_value : i32
// CHECK: llhd.process
// CHECK: llhd.wait
// CHECK-NOT: verif.assume
// CHECK: hw.output
// UNBOUNDED-LABEL: hw.module @draws(
// UNBOUNDED-COUNT-2: verif.symbolic_value : i32
// DEFAULT-LABEL: hw.module @draws(
// DEFAULT-COUNT-2: func.call @__circt_urandom_range
module draws(input bit clk, enable, input int seed_in, output int a, b, seed_out);
  int seed;
  always @(posedge clk) begin
    seed = seed_in;
    if (enable) begin
      a <= $random(seed);
      b <= $urandom(seed);
    end
    seed_out <= seed;
  end
endmodule

// CHECK-LABEL: hw.module @conditional(
// CHECK: verif.symbolic_value : i32
// CHECK: llhd.{{combinational|process}}
// CHECK: cf.cond_br
// CHECK: verif.assume
// CHECK: hw.output
// UNBOUNDED-LABEL: hw.module @conditional(
// UNBOUNDED: verif.symbolic_value : i32
// DEFAULT-LABEL: hw.module @conditional(
// DEFAULT: func.call @__circt_urandom_range
module conditional(input bit enable, nested, input int unsigned low, high,
                   output int unsigned value);
  always_comb begin
    value = 0;
    if (enable)
      if (nested) value = $urandom_range(high, low);
  end
endmodule

// The assumption stays in the positive-edge process, after the edge/enable
// branches; no clock extraction or fork-specific formal lowering is required.
// CHECK-LABEL: hw.module @positive(
// CHECK: verif.symbolic_value : i32
// CHECK: llhd.process
// CHECK: llhd.wait
// CHECK: cf.cond_br
// CHECK: verif.assume
// CHECK: hw.output
// UNBOUNDED-LABEL: hw.module @positive(
// UNBOUNDED: verif.symbolic_value : i32
// DEFAULT-LABEL: hw.module @positive(
// DEFAULT: func.call @__circt_urandom_range
module positive(input bit clk, enable, input int unsigned low, high,
                output int unsigned value);
  always @(posedge clk) if (enable) value <= $urandom_range(high, low);
endmodule

// CHECK-LABEL: hw.module @negative(
// CHECK: verif.symbolic_value : i32
// CHECK: llhd.process
// CHECK: llhd.wait
// CHECK: cf.cond_br
// CHECK: verif.assume
// CHECK: hw.output
// UNBOUNDED-LABEL: hw.module @negative(
// UNBOUNDED: verif.symbolic_value : i32
// DEFAULT-LABEL: hw.module @negative(
// DEFAULT: func.call @__circt_urandom_range
module negative(input bit clk, enable, input int unsigned high,
                output int unsigned value);
  always @(negedge clk) if (enable) value <= $urandom_range(high);
endmodule
