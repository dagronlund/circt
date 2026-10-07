// REQUIRES: verilator
// RUN: circt-opt %CIRCT_SOURCE%/test/Dialect/LLHD/Transforms/lower-formal-stream-stage.mlir --lower-llhd-formal-to-core --hw-flatten-modules --lower-seq-to-sv --lower-verif-to-sv --lower-hw-to-sv --export-verilog -o /dev/null > %t.sv
// RUN: env CCACHE_DISABLE=1 verilator --cc --exe --build --assert --coverage-user -Wno-fatal --top-module stream_stage_formal --Mdir %t.model %t.sv %S/Inputs/stream-driver.cpp > %t.build.log 2>&1
// RUN: %t.model/Vstream_stage_formal %t.coverage | FileCheck %s
// RUN: %PYTHON% %S/Inputs/check-stream-coverage.py %t.coverage
// CHECK: 10000 constrained stream-stage cycles passed
module {}
