const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const Position = errors.Position;
const SourceSpan = errors.SourceSpan;
const ZenError = errors.ZenError;

pub const TokenType = enum {
    // Literals
    identifier,
    integer,
    float,
    string,

    // Keywords
    func,
    let,
    const_kw,
    if_kw,
    else_kw,
    for_kw,
    while_kw,
    return_kw,
    true_kw,
    false_kw,
    null_kw,
    switch_kw,
    case_kw,
    default_kw,
    throw_kw,
    catch_kw,
    try_kw,
    async_kw,
    await_kw,
    type_kw,
    import_kw,
    export_kw,
    in_kw,
    is_kw,

    // Target annotations
    target_annotation, // @target
    hotpatch_annotation, // @hotpatch

    // Types
    i32_type,
    i64_type,
    f32_type,
    f64_type,
    string_type,
    bool_type,

    // Operators
    plus,
    minus,
    multiply,
    divide,
    modulo,
    assign,
    plus_assign,
    minus_assign,
    multiply_assign,
    divide_assign,

    // Comparison
    equal,
    not_equal,
    less_than,
    less_equal,
    greater_than,
    greater_equal,

    // Logical
    and_op,
    or_op,
    not_op,

    // Punctuation
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    left_bracket,
    right_bracket,
    semicolon,
    comma,
    dot,
    colon,
    question,
    exclamation,
    arrow, // ->
    double_dot, // .. (for ranges)

    // String interpolation
    interpolation_start, // ${
    interpolation_end, // }

    // Special
    newline,
    eof,

    // Comments
    comment,
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    span: SourceSpan,

    pub fn init(token_type: TokenType, lexeme: []const u8, span: SourceSpan) Token {
        return Token{
            .type = token_type,
            .lexeme = lexeme,
            .span = span,
        };
    }
};

pub const Lexer = struct {
    allocator: Allocator,
    source: []const u8,
    filename: []const u8,
    current: usize,
    line: u32,
    column: u32,
    tokens: ArrayList(Token),

    const keywords = std.StaticStringMap(TokenType).initComptime(.{
        .{ "func", .func },
        .{ "let", .let },
        .{ "const", .const_kw },
        .{ "if", .if_kw },
        .{ "else", .else_kw },
        .{ "for", .for_kw },
        .{ "while", .while_kw },
        .{ "return", .return_kw },
        .{ "true", .true_kw },
        .{ "false", .false_kw },
        .{ "null", .null_kw },
        .{ "switch", .switch_kw },
        .{ "case", .case_kw },
        .{ "default", .default_kw },
        .{ "throw", .throw_kw },
        .{ "catch", .catch_kw },
        .{ "try", .try_kw },
        .{ "async", .async_kw },
        .{ "await", .await_kw },
        .{ "type", .type_kw },
        .{ "import", .import_kw },
        .{ "export", .export_kw },
        .{ "in", .in_kw },
        .{ "is", .is_kw },
        .{ "i32", .i32_type },
        .{ "i64", .i64_type },
        .{ "f32", .f32_type },
        .{ "f64", .f64_type },
        .{ "string", .string_type },
        .{ "bool", .bool_type },
    });

    pub fn init(allocator: Allocator, source: []const u8, filename: []const u8) Lexer {
        return Lexer{
            .allocator = allocator,
            .source = source,
            .filename = filename,
            .current = 0,
            .line = 0,
            .column = 0,
            .tokens = ArrayList(Token).init(allocator),
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit();
    }

    pub fn tokenize(self: *Lexer) ZenError![]Token {
        while (!self.isAtEnd()) {
            self.scanToken() catch |err| {
                return err;
            };
        }

        try self.addToken(.eof, "");
        return self.tokens.toOwnedSlice();
    }

    fn scanToken(self: *Lexer) ZenError!void {
        const start_pos = Position.init(self.line, self.column, self.current);
        const c = self.advance();

        switch (c) {
            ' ', '\r', '\t' => {}, // Ignore whitespace
            '\n' => {
                try self.addTokenWithPos(.newline, "\n", start_pos);
                self.line += 1;
                self.column = 0;
            },
            '(' => try self.addTokenWithPos(.left_paren, "(", start_pos),
            ')' => try self.addTokenWithPos(.right_paren, ")", start_pos),
            '{' => try self.addTokenWithPos(.left_brace, "{", start_pos),
            '}' => try self.addTokenWithPos(.right_brace, "}", start_pos),
            '[' => try self.addTokenWithPos(.left_bracket, "[", start_pos),
            ']' => try self.addTokenWithPos(.right_bracket, "]", start_pos),
            ';' => try self.addTokenWithPos(.semicolon, ";", start_pos),
            ',' => try self.addTokenWithPos(.comma, ",", start_pos),
            ':' => try self.addTokenWithPos(.colon, ":", start_pos),
            '?' => try self.addTokenWithPos(.question, "?", start_pos),
            '!' => {
                const token_type: TokenType = if (self.match('=')) .not_equal else .not_op;
                const lexeme = if (token_type == .not_equal) "!=" else "!";
                try self.addTokenWithPos(token_type, lexeme, start_pos);
            },
            '=' => {
                const token_type: TokenType = if (self.match('=')) .equal else .assign;
                const lexeme = if (token_type == .equal) "==" else "=";
                try self.addTokenWithPos(token_type, lexeme, start_pos);
            },
            '+' => {
                const token_type: TokenType = if (self.match('=')) .plus_assign else .plus;
                const lexeme = if (token_type == .plus_assign) "+=" else "+";
                try self.addTokenWithPos(token_type, lexeme, start_pos);
            },
            '-' => {
                if (self.match('=')) {
                    try self.addTokenWithPos(.minus_assign, "-=", start_pos);
                } else if (self.match('>')) {
                    try self.addTokenWithPos(.arrow, "->", start_pos);
                } else {
                    try self.addTokenWithPos(.minus, "-", start_pos);
                }
            },
            '*' => {
                const token_type: TokenType = if (self.match('=')) .multiply_assign else .multiply;
                const lexeme = if (token_type == .multiply_assign) "*=" else "*";
                try self.addTokenWithPos(token_type, lexeme, start_pos);
            },
            '/' => {
                if (self.match('/')) {
                    try self.scanLineComment(start_pos);
                } else if (self.match('*')) {
                    try self.scanBlockComment(start_pos);
                } else if (self.match('=')) {
                    try self.addTokenWithPos(.divide_assign, "/=", start_pos);
                } else {
                    try self.addTokenWithPos(.divide, "/", start_pos);
                }
            },
            '%' => try self.addTokenWithPos(.modulo, "%", start_pos),
            '<' => {
                const token_type: TokenType = if (self.match('=')) .less_equal else .less_than;
                const lexeme = if (token_type == .less_equal) "<=" else "<";
                try self.addTokenWithPos(token_type, lexeme, start_pos);
            },
            '>' => {
                const token_type: TokenType = if (self.match('=')) .greater_equal else .greater_than;
                const lexeme = if (token_type == .greater_equal) ">=" else ">";
                try self.addTokenWithPos(token_type, lexeme, start_pos);
            },
            '&' => {
                if (self.match('&')) {
                    try self.addTokenWithPos(.and_op, "&&", start_pos);
                } else {
                    return ZenError.InvalidCharacter;
                }
            },
            '|' => {
                if (self.match('|')) {
                    try self.addTokenWithPos(.or_op, "||", start_pos);
                } else {
                    return ZenError.InvalidCharacter;
                }
            },
            '.' => {
                if (self.match('.')) {
                    try self.addTokenWithPos(.double_dot, "..", start_pos);
                } else {
                    try self.addTokenWithPos(.dot, ".", start_pos);
                }
            },
            '"' => try self.scanString(start_pos),
            '`' => try self.scanInterpolatedString(start_pos),
            '@' => try self.scanAnnotation(start_pos),
            else => {
                if (self.isDigit(c)) {
                    try self.scanNumber(start_pos);
                } else if (self.isAlpha(c)) {
                    try self.scanIdentifier(start_pos);
                } else {
                    return ZenError.InvalidCharacter;
                }
            },
        }
    }

    fn scanLineComment(self: *Lexer, start_pos: Position) ZenError!void {
        while (self.peek() != '\n' and !self.isAtEnd()) {
            _ = self.advance();
        }

        const lexeme = self.source[start_pos.offset..self.current];
        try self.addTokenWithPos(.comment, lexeme, start_pos);
    }

    fn scanBlockComment(self: *Lexer, start_pos: Position) ZenError!void {
        while (!self.isAtEnd()) {
            if (self.peek() == '*' and self.peekNext() == '/') {
                _ = self.advance(); // consume '*'
                _ = self.advance(); // consume '/'
                break;
            }
            if (self.advance() == '\n') {
                self.line += 1;
                self.column = 0;
            }
        }

        const lexeme = self.source[start_pos.offset..self.current];
        try self.addTokenWithPos(.comment, lexeme, start_pos);
    }

    fn scanString(self: *Lexer, start_pos: Position) ZenError!void {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 0;
            }
            _ = self.advance();
        }

        if (self.isAtEnd()) {
            return ZenError.UnexpectedEof;
        }

        _ = self.advance(); // closing "

        const lexeme = self.source[start_pos.offset..self.current];
        try self.addTokenWithPos(.string, lexeme, start_pos);
    }

    fn scanInterpolatedString(self: *Lexer, start_pos: Position) ZenError!void {
        while (!self.isAtEnd()) {
            if (self.peek() == '`') {
                _ = self.advance(); // closing `
                break;
            } else if (self.peek() == '$' and self.peekNext() == '{') {
                // Add string part before interpolation
                const string_part = self.source[start_pos.offset..self.current];
                if (string_part.len > 1) { // More than just the opening `
                    try self.addTokenWithPos(.string, string_part, start_pos);
                }

                // Add interpolation start
                _ = self.advance(); // $
                _ = self.advance(); // {
                try self.addToken(.interpolation_start, "${");

                // Scan tokens inside interpolation
                var brace_count: u32 = 1;
                while (brace_count > 0 and !self.isAtEnd()) {
                    if (self.peek() == '{') {
                        brace_count += 1;
                    } else if (self.peek() == '}') {
                        brace_count -= 1;
                        if (brace_count == 0) {
                            _ = self.advance();
                            try self.addToken(.interpolation_end, "}");
                            break;
                        }
                    }
                    try self.scanToken();
                }

                // Continue scanning the rest of the string
                return self.scanInterpolatedString(Position.init(self.line, self.column, self.current));
            } else {
                if (self.advance() == '\n') {
                    self.line += 1;
                    self.column = 0;
                }
            }
        }

        const lexeme = self.source[start_pos.offset..self.current];
        try self.addTokenWithPos(.string, lexeme, start_pos);
    }

    fn scanAnnotation(self: *Lexer, start_pos: Position) ZenError!void {
        while (self.isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }

        const lexeme = self.source[start_pos.offset..self.current];
        const token_type: TokenType = if (std.mem.eql(u8, lexeme, "@target"))
            .target_annotation
        else if (std.mem.eql(u8, lexeme, "@hotpatch"))
            .hotpatch_annotation
        else
            .identifier; // Unknown annotation treated as identifier

        try self.addTokenWithPos(token_type, lexeme, start_pos);
    }

    fn scanNumber(self: *Lexer, start_pos: Position) ZenError!void {
        while (self.isDigit(self.peek())) {
            _ = self.advance();
        }

        var token_type: TokenType = .integer;

        // Look for fractional part
        if (self.peek() == '.' and self.isDigit(self.peekNext())) {
            token_type = .float;
            _ = self.advance(); // consume '.'

            while (self.isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        const lexeme = self.source[start_pos.offset..self.current];
        try self.addTokenWithPos(token_type, lexeme, start_pos);
    }

    fn scanIdentifier(self: *Lexer, start_pos: Position) ZenError!void {
        while (self.isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }

        const lexeme = self.source[start_pos.offset..self.current];
        const token_type = keywords.get(lexeme) orelse .identifier;

        try self.addTokenWithPos(token_type, lexeme, start_pos);
    }

    fn addToken(self: *Lexer, token_type: TokenType, lexeme: []const u8) ZenError!void {
        const pos = Position.init(self.line, self.column, self.current);
        try self.addTokenWithPos(token_type, lexeme, pos);
    }

    fn addTokenWithPos(self: *Lexer, token_type: TokenType, lexeme: []const u8, start_pos: Position) ZenError!void {
        const end_pos = Position.init(self.line, self.column, self.current);
        const span = SourceSpan.init(start_pos, end_pos, self.filename);
        const token = Token.init(token_type, lexeme, span);

        self.tokens.append(token) catch {
            return ZenError.OutOfMemory;
        };
    }

    fn isAtEnd(self: *Lexer) bool {
        return self.current >= self.source.len;
    }

    fn advance(self: *Lexer) u8 {
        const c = self.source[self.current];
        self.current += 1;
        self.column += 1;
        return c;
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;

        self.current += 1;
        self.column += 1;
        return true;
    }

    fn peek(self: *Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *Lexer) u8 {
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }

    fn isDigit(self: *Lexer, c: u8) bool {
        _ = self;
        return c >= '0' and c <= '9';
    }

    fn isAlpha(self: *Lexer, c: u8) bool {
        _ = self;
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            c == '_';
    }

    fn isAlphaNumeric(self: *Lexer, c: u8) bool {
        return self.isAlpha(c) or self.isDigit(c);
    }
};

test "lexer basic tokens" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "func add(a: i32, b: i32) -> i32 { return a + b; }";

    var lexer = Lexer.init(allocator, source, "test.zen");
    defer lexer.deinit();

    const tokens = try lexer.tokenize();
    defer allocator.free(tokens);

    try testing.expect(tokens.len > 0);
    try testing.expectEqual(TokenType.func, tokens[0].type);
}
