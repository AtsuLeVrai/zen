const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const codegen = @import("codegen.zig");
const errors = @import("errors.zig");

const CompilerArgs = struct {
    input_file: ?[]const u8 = null,
    output_file: ?[]const u8 = null,
    target: Target = .native,
    mode: Mode = .release,
    show_help: bool = false,
    show_version: bool = false,

    const Target = enum {
        native,
        wasm,
        hybrid,
    };

    const Mode = enum {
        debug,
        release,
        dev,
    };
};

const VERSION = "0.1.0-alpha";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try parseArgs(allocator);
    defer if (args.input_file) |file| allocator.free(file);
    defer if (args.output_file) |file| allocator.free(file);

    if (args.show_help) {
        printHelp();
        return;
    }

    if (args.show_version) {
        print("Zen compiler version {s}\n", .{VERSION});
        return;
    }

    if (args.input_file == null) {
        print("Error: No input file specified\n", .{});
        print("Use 'zen --help' for usage information\n", .{});
        std.process.exit(1);
    }

    try compileFile(allocator, args);
}

fn parseArgs(allocator: Allocator) !CompilerArgs {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var result = CompilerArgs{};
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.show_help = true;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            result.show_version = true;
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) {
                print("Error: --target requires an argument\n", .{});
                std.process.exit(1);
            }
            const target_str = args[i];
            if (std.mem.eql(u8, target_str, "native")) {
                result.target = .native;
            } else if (std.mem.eql(u8, target_str, "wasm")) {
                result.target = .wasm;
            } else if (std.mem.eql(u8, target_str, "hybrid")) {
                result.target = .hybrid;
            } else {
                print("Error: Unknown target '{s}'\n", .{target_str});
                std.process.exit(1);
            }
        } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "-o")) {
            i += 1;
            if (i >= args.len) {
                print("Error: --output requires an argument\n", .{});
                std.process.exit(1);
            }
            result.output_file = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--dev")) {
            result.mode = .dev;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            result.mode = .debug;
        } else if (!std.mem.startsWith(u8, arg, "-")) {
            if (result.input_file == null) {
                result.input_file = try allocator.dupe(u8, arg);
            } else {
                print("Error: Multiple input files specified\n", .{});
                std.process.exit(1);
            }
        } else {
            print("Error: Unknown option '{s}'\n", .{arg});
            std.process.exit(1);
        }
    }

    return result;
}

fn printHelp() void {
    print("Zen Programming Language Compiler v{s}\n\n", .{VERSION});
    print("USAGE:\n", .{});
    print("    zen [OPTIONS] <INPUT_FILE>\n\n", .{});
    print("OPTIONS:\n", .{});
    print("    -h, --help        Show this help message\n", .{});
    print("    -v, --version     Show version information\n", .{});
    print("    -o, --output      Specify output file\n", .{});
    print("        --target      Compilation target (native, wasm, hybrid)\n", .{});
    print("        --dev         Development mode with hot-patching\n", .{});
    print("        --debug       Debug mode with extra information\n\n", .{});
    print("EXAMPLES:\n", .{});
    print("    zen main.zen\n", .{});
    print("    zen --target wasm --output app.wasm main.zen\n", .{});
    print("    zen --dev --target hybrid main.zen\n\n", .{});
    print("For more information, visit: https://github.com/zen-lang/zen\n", .{});
}

fn compileFile(allocator: Allocator, args: CompilerArgs) !void {
    const input_file = args.input_file.?;

    print("🔨 Compiling '{s}' (target: {s}, mode: {s})\n", .{ input_file, @tagName(args.target), @tagName(args.mode) });

    // Read source file
    const source = std.fs.cwd().readFileAlloc(allocator, input_file, std.math.maxInt(usize)) catch |err| switch (err) {
        error.FileNotFound => {
            errors.reportError(allocator, "File not found: {s}", .{input_file});
            std.process.exit(1);
        },
        else => return err,
    };
    defer allocator.free(source);

    // Lexical analysis
    print("📝 Lexical analysis...\n", .{});
    var lex = lexer.Lexer.init(allocator, source, input_file);
    defer lex.deinit();

    const tokens = lex.tokenize() catch |err| {
        print("❌ Lexical analysis failed\n", .{});
        return err;
    };

    if (args.mode == .debug) {
        print("🔍 Tokens found: {d}\n", .{tokens.len});
    }

    // Parsing
    print("🧩 Parsing...\n", .{});
    var pars = parser.Parser.init(allocator, tokens, input_file);
    defer pars.deinit();

    const ast = pars.parse() catch |err| {
        print("❌ Parsing failed\n", .{});
        return err;
    };

    // Code generation
    print("⚡ Code generation...\n", .{});
    const target: codegen.CodeGen.Target = switch (args.target) {
        .native => .native,
        .wasm => .wasm,
        .hybrid => .hybrid,
    };
    var gen = codegen.CodeGen.init(allocator, target);
    defer gen.deinit();

    const output = gen.generate(ast) catch |err| {
        print("❌ Code generation failed\n", .{});
        return err;
    };

    // Write output
    const output_file = args.output_file orelse switch (args.target) {
        .native => "output",
        .wasm => "output.wasm",
        .hybrid => "output_hybrid",
    };

    try std.fs.cwd().writeFile(.{ .sub_path = output_file, .data = output });

    print("✅ Compilation successful!\n", .{});
    print("📦 Output: {s}\n", .{output_file});

    if (args.mode == .dev) {
        print("⚡ Hot-patching enabled for development\n", .{});
        print("🔍 Watching for file changes...\n", .{});
    }
}
