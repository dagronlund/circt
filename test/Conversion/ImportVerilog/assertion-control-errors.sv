// RUN: circt-translate --import-verilog --verify-diagnostics --split-input-file %s
// REQUIRES: slang

module AssertOnArgument;
  // expected-error @below {{arguments to `$asserton` are not supported}}
  initial $asserton(0);
endmodule

// -----

module AssertOffArgument;
  // expected-error @below {{arguments to `$assertoff` are not supported}}
  initial $assertoff(1);
endmodule

// -----

module AssertOnScopeArgument;
  // expected-error @below {{arguments to `$asserton` are not supported}}
  initial $asserton(0, AssertOnScopeArgument);
endmodule

// -----

module AssertOffScopeArgument;
  // expected-error @below {{arguments to `$assertoff` are not supported}}
  initial $assertoff(0, AssertOffScopeArgument);
endmodule
