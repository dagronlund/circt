// RUN: circt-verilog --ir-moore %s | FileCheck %s
// RUN: circt-verilog --ir-hw %s > /dev/null
// REQUIRES: slang

module source(input logic a);
  logic internal_signal;
  assign internal_signal = a;
endmodule

module sink(input logic value, output logic result);
  assign result = value;
endmodule

// An input connection can refer to a later instance's internal signal.
// CHECK-LABEL: moore.module @top(
// CHECK: %[[VALUE:.*]] = moore.read %[[REF:.*]] : <l1>
// CHECK: moore.instance "s" @sink(value: %[[VALUE]]
// CHECK: %[[REF]] = moore.instance "u" @source
module top(input logic a, output logic result);
  sink s(.value(u.internal_signal), .result(result));
  source u(.a(a));
endmodule

// Both instances can refer to each other; sorting instances is insufficient.
// CHECK-LABEL: moore.module @MutualReferences(
// CHECK: %[[B_VALUE:.*]] = moore.read %[[B_REF:.*]] : <l1>
// CHECK: %[[A_REF:.*]] = moore.instance "a" @source(a: %[[B_VALUE]]
// CHECK: %[[A_VALUE:.*]] = moore.read %[[A_REF]] : <l1>
// CHECK: %[[B_REF]] = moore.instance "b" @source(a: %[[A_VALUE]]
module MutualReferences(output logic result);
  source a(.a(b.internal_signal));
  source b(.a(a.internal_signal));
  assign result = a.internal_signal;
endmodule

module storage;
  logic value;
endmodule

// Output connections also need forward references, including across generate
// scopes.
// CHECK-LABEL: moore.module @ForwardOutput(
// CHECK: %[[OUT:.*]] = moore.instance "s" @sink
// CHECK: moore.assign %[[REF:.*]], %[[OUT]] : l1
// CHECK: %[[REF]] = moore.instance "g.u" @storage
module ForwardOutput(input logic a, output logic result);
  sink s(.value(a), .result(g.u.value));
  if (1) begin : g
    storage u();
  end
  assign result = g.u.value;
endmodule
