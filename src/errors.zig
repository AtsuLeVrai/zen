const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

pub const Position = struct {
    line: u32,
    column: u32,
    offset: usize,

    pub fn init(line: u32, column: u32, offset: usize) Position {
        return Position{
            .line = line,
            .column = column,
            .offset = offset,
        };
    }
};

pub const SourceSpan = struct {
    start: Position,
    end: Position,
    filename: []const u8,

    pub fn init(start: Position, end: Position, filename: []const u8) SourceSpan {
        return SourceSpan{
            .start = start,
            .end = end,
            .filename = filename,
        };
    }
};

pub const CompilerError = struct {
    message: []const u8,
    span: ?SourceSpan,
    error_type: ErrorType,
    suggestions: []const []const u8,

    pub const ErrorType = enum {
        lexer_error,
        parser_error,
        type_error,
        codegen_error,
        io_error,
    };

    pub fn init(allocator: Allocator, message: []const u8, span: ?SourceSpan, error_type: ErrorType) !CompilerError {
        return CompilerError{
            .message = try allocator.dupe(u8, message),
            .span = span,
            .error_type = error_type,
            .suggestions = &[_][]const u8{},
        };
    }

    pub fn withSuggestion(self: *CompilerError, allocator: Allocator, suggestion: []const u8) !void {
        const new_suggestions = try allocator.alloc([]const u8, self.suggestions.len + 1);
        @memcpy(new_suggestions[0..self.suggestions.len], self.suggestions);
        new_suggestions[self.suggestions.len] = try allocator.dupe(u8, suggestion);
        self.suggestions = new_suggestions;
    }

    pub fn deinit(self: *CompilerError, allocator: Allocator) void {
        allocator.free(self.message);
        for (self.suggestions) |suggestion| {
            allocator.free(suggestion);
        }
        allocator.free(self.suggestions);
    }
};

pub fn reportError(allocator: Allocator, comptime fmt: []const u8, args: anytype) void {
    _ = allocator;
    print("❌ Error: ", .{});
    print(fmt, args);
    print("\n", .{});
}

pub fn reportErrorWithSpan(source: []const u8, error_info: CompilerError) void {
    print("❌ {s} Error: {s}\n", .{ @tagName(error_info.error_type), error_info.message });

    if (error_info.span) |span| {
        print("   --> {s}:{}:{}\n", .{ span.filename, span.start.line + 1, span.start.column + 1 });

        // Find the line in source
        var line_start: usize = 0;
        var line_num: u32 = 0;
        var i: usize = 0;

        while (i < source.len) : (i += 1) {
            if (source[i] == '\n') {
                line_num += 1;
                if (line_num > span.start.line) break;
                line_start = i + 1;
            }
        }

        // Extract the line
        var line_end = line_start;
        while (line_end < source.len and source[line_end] != '\n') {
            line_end += 1;
        }

        const line_content = source[line_start..line_end];

        // Print line number and content
        print("    |\n");
        print("{d:3} | {s}\n", .{ span.start.line + 1, line_content });

        // Print pointer to error location
        print("    | ");
        for (0..span.start.column) |_| {
            print(" ");
        }

        const error_length = if (span.end.line == span.start.line)
            @max(1, span.end.column - span.start.column)
        else
            1;

        for (0..error_length) |_| {
            print("^");
        }
        print("\n");

        if (error_info.suggestions.len > 0) {
            print("    |\n");
            print("Help: Did you mean?\n");
            for (error_info.suggestions) |suggestion| {
                print("   • {s}\n", .{suggestion});
            }
        }
    }

    print("\n");
}

pub const ZenError = error{
    LexerError,
    ParserError,
    TypeError,
    CodegenError,
    OutOfMemory,
    Overflow,
    InvalidCharacter,
    UnexpectedToken,
    UnexpectedEof,
    FileNotFound,
    InvalidSyntax,
    InvalidNodeId,
};

test "error reporting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const pos = Position.init(0, 5, 5);
    const span = SourceSpan.init(pos, pos, "test.zen");

    var err = try CompilerError.init(allocator, "Test error", span, .lexer_error);
    defer err.deinit(allocator);

    try err.withSuggestion(allocator, "Try this instead");

    try testing.expectEqual(@as(usize, 1), err.suggestions.len);
}
