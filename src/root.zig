// Zen Programming Language Compiler
// Root module for the library components

pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const ast = @import("ast.zig");
pub const types = @import("types.zig");
pub const checker = @import("checker.zig");
pub const codegen = @import("codegen.zig");

pub fn version() []const u8 {
    return "0.1.0-phase1";
}