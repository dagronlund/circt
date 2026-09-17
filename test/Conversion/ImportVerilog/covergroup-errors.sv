// RUN: circt-translate --import-verilog --verify-diagnostics --split-input-file %s
// REQUIRES: slang

module top;
  covergroup cg with function sample(int value);
    // expected-error @below {{unsupported coverpoint options}}
    cp: coverpoint value { option.at_least = 2; }
  endgroup
  cg coverage = new();
endmodule

// -----
module top;
  bit clk;
  covergroup cg @(posedge clk);
    coverpoint clk;
  endgroup
  cg coverage;
  // expected-error @below {{clocked covergroups require a module-level initializer}}
  initial coverage = new();
endmodule

// -----
module top;
  covergroup cg with function sample(int value);
    a: coverpoint value;
    b: coverpoint value;
    // expected-error @below {{unsupported covergroup cross}}
    cross a, b;
  endgroup
  cg coverage = new();
endmodule

// -----
module top;
  covergroup cg(int arg);
    // expected-error @below {{unsupported coverpoint expression: expected sample inputs and constants}}
    coverpoint arg;
  endgroup
  cg coverage = new(1);
endmodule

// -----
module top;
  // expected-error @below {{unsupported covergroup sample argument direction}}
  covergroup cg with function sample(ref int value);
    coverpoint value;
  endgroup
  cg coverage = new();
endmodule

// -----
module top;
  covergroup cg with function sample(int value);
    coverpoint value;
  endgroup
  cg coverage = new();
  // expected-error @below {{unsupported covergroup method: start}}
  initial coverage.start();
endmodule

// -----
module top;
  typedef enum { A, B } state;
  covergroup cg with function sample(state value);
    // expected-error @below {{unsupported enum coverpoint automatic bins}}
    coverpoint value;
  endgroup
  cg coverage = new();
endmodule

// -----
module top;
  // expected-error @below {{unsupported covergroup inheritance or options}}
  covergroup cg with function sample(int value);
    option.at_least = 2;
    coverpoint value;
  endgroup
  cg coverage = new();
endmodule

// -----
module top;
  int limit;
  // expected-error @below {{unsupported covergroup constructor argument direction}}
  covergroup cg(ref int arg) with function sample(int value);
    coverpoint value;
  endgroup
  cg coverage = new(limit);
endmodule

// -----
module top;
  covergroup cg(int limit) with function sample(int value);
    // expected-error @below {{unsupported coverpoint expression: expected sample inputs and constants}}
    coverpoint value iff (value < limit);
  endgroup
  cg coverage = new(4);
endmodule

// -----
module top;
  bit enabled;
  // expected-error @below {{unsupported covergroup inheritance or options}}
  covergroup cg with function sample(int value);
    option.per_instance = enabled;
    coverpoint value;
  endgroup
  cg coverage = new();
endmodule

// -----
module top;
  covergroup cg with function sample(bit value);
    coverpoint value {
      // expected-error @below {{unsupported coverage bin: expected a scalar value bin or illegal bin}}
      bins values[] = {0, 1};
    }
  endgroup
  cg coverage = new;
endmodule

// -----
module top;
  covergroup cg with function sample(bit [3:0] value);
    coverpoint value {
      // expected-error @below {{unsupported coverage bin value: expected an integral constant}}
      bins values = {[0:3]};
    }
  endgroup
  cg coverage = new;
endmodule
