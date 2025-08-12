//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    
    try stdout.print("Zen Language Compiler v2.0\n", .{});
    try stdout.print("===========================\n\n", .{});
    
    const sample_code = 
        \\func fibonacci(n: i32) -> i32 {
        \\    if (n <= 1) {
        \\        return n;
        \\    }
        \\    return fibonacci(n - 1) + fibonacci(n - 2);
        \\}
        \\
        \\func main() -> i32 {
        \\    let result = fibonacci(10);
        \\    let message = "Result: ${result}";
        \\    return 0;
        \\}
    ;
    
    try stdout.print("Sample Zen code:\n{s}\n\n", .{sample_code});
    
    var lexer_instance = try lib.lexer.Lexer.init(allocator, sample_code);
    defer lexer_instance.deinit();
    
    var parser_instance = lib.parser.Parser.init(allocator, &lexer_instance);
    defer parser_instance.deinit();
    
    try stdout.print("Parsing program...\n", .{});
    const program = parser_instance.parse() catch |err| {
        try stdout.print("Parse error: {}\n", .{err});
        if (parser_instance.errors.items.len > 0) {
            try stdout.print("Error details:\n", .{});
            for (parser_instance.errors.items) |error_info| {
                try stdout.print("  Line {}, Column {}: {s}\n", .{
                    error_info.position.line,
                    error_info.position.column,
                    error_info.message
                });
            }
        }
        return;
    };
    
    try stdout.print("Successfully parsed {} function(s)!\n", .{program.functions.len});
    
    try stdout.print("\nProgram structure:\n", .{});
    try stdout.print("------------------\n", .{});
    
    for (program.functions, 0..) |func, i| {
        try stdout.print("Function {}: {s}\n", .{i + 1, func.name});
        try stdout.print("  Parameters: {}\n", .{func.parameters.len});
        for (func.parameters) |param| {
            const type_name = switch (param.param_type.kind) {
                .i32 => "i32",
                .f64 => "f64",
                .string => "string",
                .bool => "bool",
                .void => "void",
                .optional => "optional",
                .array => "array",
                .custom => param.param_type.name orelse "unknown",
            };
            try stdout.print("    - {s}: {s}\n", .{param.name, type_name});
        }
        
        const return_type_name = if (func.return_type) |rt| switch (rt.kind) {
            .i32 => "i32",
            .f64 => "f64", 
            .string => "string",
            .bool => "bool",
            .void => "void",
            .optional => "optional",
            .array => "array",
            .custom => rt.name orelse "unknown",
        } else "none";
        
        try stdout.print("  Return type: {s}\n", .{return_type_name});
        try stdout.print("  Body: {s}\n", .{@tagName(func.body.kind)});
    }
    
    try stdout.print("\nRun `zig build test` to run the comprehensive test suite.\n", .{});
    
    try bw.flush();
}

test "lexer integration test" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    
    const source = "let x = 42;";
    var lexer_instance = try lib.lexer.Lexer.init(arena.allocator(), source);
    defer lexer_instance.deinit();
    
    const let_token = try lexer_instance.nextToken();
    try std.testing.expectEqual(lib.lexer.TokenType.let, let_token.type);
    
    const x_token = try lexer_instance.nextToken();
    try std.testing.expectEqual(lib.lexer.TokenType.identifier, x_token.type);
    
    const assign_token = try lexer_instance.nextToken();
    try std.testing.expectEqual(lib.lexer.TokenType.assign, assign_token.type);
    
    const num_token = try lexer_instance.nextToken();
    try std.testing.expectEqual(lib.lexer.TokenType.integer, num_token.type);
}

const std = @import("std");

/// This imports the separate module containing `root.zig`. Take a look in `build.zig` for details.
const lib = @import("zen_lib");
