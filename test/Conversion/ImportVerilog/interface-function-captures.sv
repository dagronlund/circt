// RUN: circt-verilog --ir-moore %s | FileCheck %s
// RUN: circt-verilog --ir-hw %s > /dev/null
// REQUIRES: slang
// UNSUPPORTED: valgrind

// Interface members used in subroutines must be captured, including modport
// inputs flattened to value-typed module ports. Captures also propagate through
// calls and support writes to modport outputs and unrestricted interface ports.
interface CaptureBus;
  logic valid;
  logic result;
  modport monitor(input valid, output result);
endinterface

// CHECK-LABEL: moore.module private @CaptureReader(in %bus_valid : !moore.l1,
// CHECK: [[VALID:%.+]] = moore.variable name "bus_valid" : <l1>
// CHECK: moore.assign [[VALID]], %bus_valid : l1
// CHECK: [[RESULT:%.+]] = moore.variable : <l1>
// CHECK: func.call @set_result([[RESULT]], [[VALID]]) : (!moore.ref<l1>, !moore.ref<l1>) -> !moore.l1
module CaptureReader(CaptureBus.monitor bus, output logic result);
  // CHECK-LABEL: func.func private @get_valid(%arg0: !moore.ref<l1>)
  // CHECK: [[READ:%.+]] = moore.read %arg0 : <l1>
  // CHECK: return [[READ]] : !moore.l1
  function automatic logic get_valid();
    return bus.valid;
  endfunction
  // CHECK-LABEL: func.func private @wrapped(%arg0: !moore.ref<l1>)
  // CHECK: call @get_valid(%arg0) : (!moore.ref<l1>) -> !moore.l1
  function automatic logic wrapped();
    return get_valid();
  endfunction
  // CHECK-LABEL: func.func private @set_result(%arg0: !moore.ref<l1>, %arg1: !moore.ref<l1>)
  // CHECK: [[WRAPPED:%.+]] = call @wrapped(%arg1) : (!moore.ref<l1>) -> !moore.l1
  // CHECK: moore.blocking_assign %arg0, [[WRAPPED]] : l1
  // CHECK: moore.read %arg0 : <l1>
  function automatic logic set_result();
    bus.result = wrapped();
    return bus.result;
  endfunction
  assign result = set_result();
endmodule

// CHECK-LABEL: moore.module private @CaptureUnrestricted(in %bus_valid : !moore.ref<l1>,
// CHECK: func.call @get_unrestricted(%bus_valid) : (!moore.ref<l1>) -> !moore.l1
module CaptureUnrestricted(CaptureBus bus, output logic result);
  // CHECK-LABEL: func.func private @get_unrestricted(%arg0: !moore.ref<l1>)
  // CHECK: moore.read %arg0 : <l1>
  function automatic logic get_unrestricted();
    return bus.valid;
  endfunction
  assign result = get_unrestricted();
endmodule

module InterfaceFunctionCaptures(input logic valid, output logic result,
                                 output logic unrestricted_result);
  CaptureBus bus();
  assign bus.valid = valid;
  CaptureReader reader(bus, result);
  CaptureUnrestricted unrestricted(bus, unrestricted_result);
endmodule
