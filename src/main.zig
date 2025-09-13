const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const types = @import("types.zig");
const checker = @import("checker.zig");
const codegen = @import("codegen.zig");

const CompilerError = error{
    InvalidArguments,
    FileNotFound,
    CompilationFailed,
    OutOfMemory,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: zenc <source_file.zen>\n", .{});
        std.debug.print("Zen Programming Language Compiler - Phase 1\n", .{});
        return CompilerError.InvalidArguments;
    }

    const source_file = args[1];
    std.debug.print("Compiling: {s}\n", .{source_file});

    // Read source file
    const file_contents = std.fs.cwd().readFileAlloc(allocator, source_file, std.math.maxInt(usize)) catch |err| {
        std.debug.print("Error reading file '{s}': {}\n", .{ source_file, err });
        return CompilerError.FileNotFound;
    };
    defer allocator.free(file_contents);

    // Compilation pipeline
    try compileZenSource(allocator, file_contents, source_file);
}

fn compileZenSource(allocator: std.mem.Allocator, source: []const u8, filename: []const u8) !void {
    std.debug.print("Phase 1: Lexical Analysis\n", .{});

    // Tokenize
    var tokenizer = lexer.Lexer.init(allocator, source);
    defer tokenizer.deinit();

    const tokens = try tokenizer.tokenize();
    defer allocator.free(tokens);
    std.debug.print("Generated {} tokens\n", .{tokens.len});

    std.debug.print("Phase 2: Syntax Analysis\n", .{});

    // Parse
    var zen_parser = parser.Parser.init(allocator, tokens);
    defer zen_parser.deinit();

    const syntax_tree = try zen_parser.parseProgram();
    defer ast.destroyNode(allocator, syntax_tree);
    std.debug.print("Built AST with {} nodes\n", .{syntax_tree.data.program.statements.len});

    std.debug.print("Phase 3: Type Checking\n", .{});

    // Type check
    var type_checker = checker.TypeChecker.init(allocator);
    defer type_checker.deinit();

    try type_checker.checkProgram(syntax_tree);
    std.debug.print("Type checking passed\n", .{});

    std.debug.print("Phase 4: Code Generation\n", .{});

    // Generate LLVM IR
    var code_generator = codegen.CodeGenerator.init(allocator);
    defer code_generator.deinit();

    try code_generator.generateProgram(syntax_tree, filename);
    std.debug.print("Code generation complete\n", .{});

    std.debug.print("Compilation successful!\n", .{});
}
