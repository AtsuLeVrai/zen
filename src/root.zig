//! Zen Programming Language Compiler Library
//! This is the library interface for the Zen compiler components.

const std = @import("std");
const testing = std.testing;

// Export all main compiler modules
pub const lexer = @import("lexer.zig");
pub const parser = @import("parser.zig");
pub const ast = @import("ast.zig");
pub const codegen = @import("codegen.zig");
pub const errors = @import("errors.zig");

// Main compiler API
pub const Compiler = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Compiler {
        return Compiler{
            .allocator = allocator,
        };
    }

    pub fn compile(self: *Compiler, source: []const u8, filename: []const u8, target: CompilerTarget) ![]u8 {
        // Lexical analysis
        var lex = lexer.Lexer.init(self.allocator, source, filename);
        defer lex.deinit();

        const tokens = try lex.tokenize();
        defer self.allocator.free(tokens);

        // Parsing
        var pars = parser.Parser.init(self.allocator, tokens, filename);
        defer pars.deinit();

        const ast_result = try pars.parse();

        // Code generation
        var gen = codegen.CodeGen.init(self.allocator, switch (target) {
            .native => .native,
            .wasm => .wasm,
            .hybrid => .hybrid,
        });
        defer gen.deinit();

        return try gen.generate(ast_result);
    }

    pub const CompilerTarget = enum {
        native,
        wasm,
        hybrid,
    };
};

// Version information
pub const VERSION = "0.1.0-alpha";
pub const VERSION_MAJOR = 0;
pub const VERSION_MINOR = 1;
pub const VERSION_PATCH = 0;

// Feature flags
pub const Features = struct {
    pub const SUPPORTS_HOT_PATCHING = true;
    pub const SUPPORTS_MULTI_TARGET = true;
    pub const SUPPORTS_ERROR_PROPAGATION = true;
    pub const SUPPORTS_STRING_INTERPOLATION = true;
    pub const SUPPORTS_TYPE_INFERENCE = false; // Not yet implemented
    pub const SUPPORTS_ASYNC_AWAIT = false; // Not yet implemented
};

// Utility functions for external tools
pub fn getVersion() []const u8 {
    return VERSION;
}

pub fn getSupportedTargets() []const []const u8 {
    return &[_][]const u8{ "native", "wasm", "hybrid" };
}

pub fn isValidZenFile(filename: []const u8) bool {
    return std.mem.endsWith(u8, filename, ".zen");
}

// Legacy function for compatibility
pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}

// Tests
test "basic add functionality" {
    try testing.expect(add(3, 7) == 10);
}

test "compiler initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const compiler = Compiler.init(allocator);
    _ = compiler; // Just test initialization

    try testing.expect(true);
}

test "version information" {
    try testing.expect(VERSION_MAJOR == 0);
    try testing.expect(VERSION_MINOR == 1);
    try testing.expect(VERSION_PATCH == 0);

    const version = getVersion();
    try testing.expect(std.mem.eql(u8, version, "0.1.0-alpha"));
}

test "zen file validation" {
    try testing.expect(isValidZenFile("test.zen"));
    try testing.expect(isValidZenFile("hello_world.zen"));
    try testing.expect(!isValidZenFile("test.zig"));
    try testing.expect(!isValidZenFile("test.c"));
    try testing.expect(!isValidZenFile("test"));
}
