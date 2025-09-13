const std = @import("std");

pub const TokenType = enum {
    // Keywords
    fn_,
    const_,
    let_,
    return_,
    if_,
    else_,
    while_,
    for_,
    true_,
    false_,

    // Types
    i32,
    f64,
    bool,
    void,
    string,

    // Literals
    number,
    string_literal,
    identifier,

    // Operators
    plus,
    minus,
    star,
    slash,
    equal,
    equal_equal,
    bang_equal,
    less,
    less_equal,
    greater,
    greater_equal,
    bang,

    // Punctuation
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    comma,
    semicolon,
    colon,
    arrow, // ->

    // Special
    eof,
    error_,
    newline,
    whitespace,

    pub fn toString(self: TokenType) []const u8 {
        return switch (self) {
            .fn_ => "fn",
            .const_ => "const",
            .let_ => "let",
            .return_ => "return",
            .if_ => "if",
            .else_ => "else",
            .while_ => "while",
            .for_ => "for",
            .true_ => "true",
            .false_ => "false",
            .i32 => "i32",
            .f64 => "f64",
            .bool => "bool",
            .void => "void",
            .string => "string",
            .number => "NUMBER",
            .string_literal => "STRING",
            .identifier => "IDENTIFIER",
            .plus => "+",
            .minus => "-",
            .star => "*",
            .slash => "/",
            .equal => "=",
            .equal_equal => "==",
            .bang_equal => "!=",
            .less => "<",
            .less_equal => "<=",
            .greater => ">",
            .greater_equal => ">=",
            .bang => "!",
            .left_paren => "(",
            .right_paren => ")",
            .left_brace => "{",
            .right_brace => "}",
            .comma => ",",
            .semicolon => ";",
            .colon => ":",
            .arrow => "->",
            .eof => "EOF",
            .error_ => "ERROR",
            .newline => "NEWLINE",
            .whitespace => "WHITESPACE",
        };
    }
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: u32,
    column: u32,
};

pub const LexerError = error{
    UnterminatedString,
    InvalidCharacter,
    OutOfMemory,
};

pub const Lexer = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    source: []const u8,
    tokens: std.ArrayList(Token),
    start: usize,
    current: usize,
    line: u32,
    column: u32,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Self {
        return Self{
            .allocator = allocator,
            .source = source,
            .tokens = std.ArrayList(Token){},
            .start = 0,
            .current = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn deinit(self: *Self) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn tokenize(self: *Self) ![]Token {
        while (!self.isAtEnd()) {
            self.start = self.current;
            try self.scanToken();
        }

        try self.tokens.append(self.allocator, Token{
            .type = .eof,
            .lexeme = "",
            .line = self.line,
            .column = self.column,
        });

        return self.tokens.toOwnedSlice(self.allocator);
    }

    fn isAtEnd(self: *Self) bool {
        return self.current >= self.source.len;
    }

    fn scanToken(self: *Self) !void {
        const c = self.advance();

        switch (c) {
            ' ', '\r', '\t' => {
                // Skip whitespace
            },
            '\n' => {
                self.line += 1;
                self.column = 1;
            },
            '(' => try self.addToken(.left_paren),
            ')' => try self.addToken(.right_paren),
            '{' => try self.addToken(.left_brace),
            '}' => try self.addToken(.right_brace),
            ',' => try self.addToken(.comma),
            ';' => try self.addToken(.semicolon),
            ':' => try self.addToken(.colon),
            '+' => try self.addToken(.plus),
            '*' => try self.addToken(.star),
            '/' => {
                if (self.match('/')) {
                    // Line comment - skip until end of line
                    while (self.peek() != '\n' and !self.isAtEnd()) {
                        _ = self.advance();
                    }
                } else {
                    try self.addToken(.slash);
                }
            },
            '-' => {
                if (self.match('>')) {
                    try self.addToken(.arrow);
                } else {
                    try self.addToken(.minus);
                }
            },
            '!' => {
                if (self.match('=')) {
                    try self.addToken(.bang_equal);
                } else {
                    try self.addToken(.bang);
                }
            },
            '=' => {
                if (self.match('=')) {
                    try self.addToken(.equal_equal);
                } else {
                    try self.addToken(.equal);
                }
            },
            '<' => {
                if (self.match('=')) {
                    try self.addToken(.less_equal);
                } else {
                    try self.addToken(.less);
                }
            },
            '>' => {
                if (self.match('=')) {
                    try self.addToken(.greater_equal);
                } else {
                    try self.addToken(.greater);
                }
            },
            '"' => try self.scanString(),
            else => {
                if (isDigit(c)) {
                    try self.scanNumber();
                } else if (isAlpha(c)) {
                    try self.scanIdentifier();
                } else {
                    return LexerError.InvalidCharacter;
                }
            },
        }
    }

    fn advance(self: *Self) u8 {
        self.column += 1;
        const c = self.source[self.current];
        self.current += 1;
        return c;
    }

    fn match(self: *Self, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;

        self.current += 1;
        self.column += 1;
        return true;
    }

    fn peek(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *Self) u8 {
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }

    fn scanString(self: *Self) !void {
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            _ = self.advance();
        }

        if (self.isAtEnd()) {
            return LexerError.UnterminatedString;
        }

        // Closing "
        _ = self.advance();

        // Trim the surrounding quotes
        const value = self.source[self.start + 1 .. self.current - 1];
        try self.addTokenWithLexeme(.string_literal, value);
    }

    fn scanNumber(self: *Self) !void {
        while (isDigit(self.peek())) {
            _ = self.advance();
        }

        // Look for fractional part
        if (self.peek() == '.' and isDigit(self.peekNext())) {
            // Consume the "."
            _ = self.advance();

            while (isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        try self.addToken(.number);
    }

    fn scanIdentifier(self: *Self) !void {
        while (isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }

        const text = self.source[self.start..self.current];
        const token_type = getKeywordType(text) orelse .identifier;
        try self.addToken(token_type);
    }

    fn addToken(self: *Self, token_type: TokenType) !void {
        const text = self.source[self.start..self.current];
        try self.addTokenWithLexeme(token_type, text);
    }

    fn addTokenWithLexeme(self: *Self, token_type: TokenType, lexeme: []const u8) !void {
        try self.tokens.append(self.allocator, Token{
            .type = token_type,
            .lexeme = lexeme,
            .line = self.line,
            .column = self.column - @as(u32, @intCast(lexeme.len)),
        });
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            c == '_';
    }

    fn isAlphaNumeric(c: u8) bool {
        return isAlpha(c) or isDigit(c);
    }

    fn getKeywordType(text: []const u8) ?TokenType {
        if (std.mem.eql(u8, text, "fn")) return .fn_;
        if (std.mem.eql(u8, text, "const")) return .const_;
        if (std.mem.eql(u8, text, "let")) return .let_;
        if (std.mem.eql(u8, text, "return")) return .return_;
        if (std.mem.eql(u8, text, "if")) return .if_;
        if (std.mem.eql(u8, text, "else")) return .else_;
        if (std.mem.eql(u8, text, "while")) return .while_;
        if (std.mem.eql(u8, text, "for")) return .for_;
        if (std.mem.eql(u8, text, "true")) return .true_;
        if (std.mem.eql(u8, text, "false")) return .false_;
        if (std.mem.eql(u8, text, "i32")) return .i32;
        if (std.mem.eql(u8, text, "f64")) return .f64;
        if (std.mem.eql(u8, text, "bool")) return .bool;
        if (std.mem.eql(u8, text, "void")) return .void;
        if (std.mem.eql(u8, text, "string")) return .string;
        return null;
    }
};

// Helper function for debugging
pub fn printTokens(tokens: []Token) void {
    std.debug.print("Tokens:\n");
    for (tokens) |token| {
        std.debug.print("  {s}: '{s}' at {}:{}\n", .{ token.type.toString(), token.lexeme, token.line, token.column });
    }
}