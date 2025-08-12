const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const unicode = @import("unicode.zig");

pub const TokenType = enum {
    // Literals
    integer,
    float,
    string,
    boolean,
    null_literal,
    
    // Identifiers and Keywords
    identifier,
    func,
    let,
    const_keyword,
    return_keyword,
    if_keyword,
    else_keyword,
    for_keyword,
    while_keyword,
    switch_keyword,
    case_keyword,
    default_keyword,
    type_keyword,
    import_keyword,
    export_keyword,
    async_keyword,
    await_keyword,
    throw_keyword,
    catch_keyword,
    try_keyword,
    in_keyword,
    
    // Operators
    plus,
    minus,
    multiply,
    divide,
    modulo,
    equal_equal,
    not_equal,
    less_than,
    greater_than,
    less_equal,
    greater_equal,
    logical_and,
    logical_or,
    logical_not,
    assign,
    plus_assign,
    minus_assign,
    multiply_assign,
    divide_assign,
    is_keyword,
    
    // Delimiters
    left_brace,
    right_brace,
    left_paren,
    right_paren,
    left_bracket,
    right_bracket,
    semicolon,
    colon,
    comma,
    arrow,
    question,
    at_sign,
    
    // Special
    eof,
    newline,
    whitespace,
    comment,
    
    // Error tokens
    invalid,
    unterminated_string,
    invalid_number,
};

pub const Position = struct {
    line: u32,
    column: u32,
    offset: u32,
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    position: Position,
    
    pub fn init(token_type: TokenType, lexeme: []const u8, position: Position) Token {
        return Token{
            .type = token_type,
            .lexeme = lexeme,
            .position = position,
        };
    }
};

pub const LexerError = error{
    UnterminatedString,
    InvalidNumber,
    InvalidCharacter,
    OutOfMemory,
};

const KeywordMap = std.HashMap([]const u8, TokenType, std.hash_map.StringContext, 80);

pub const Lexer = struct {
    source: []const u8,
    current: u32,
    start: u32,
    line: u32,
    column: u32,
    keywords: KeywordMap,
    arena: ArenaAllocator,
    
    pub fn init(allocator: Allocator, source: []const u8) !Lexer {
        var arena = ArenaAllocator.init(allocator);
        var keywords = KeywordMap.init(arena.allocator());
        
        try keywords.put("func", .func);
        try keywords.put("let", .let);
        try keywords.put("const", .const_keyword);
        try keywords.put("return", .return_keyword);
        try keywords.put("if", .if_keyword);
        try keywords.put("else", .else_keyword);
        try keywords.put("for", .for_keyword);
        try keywords.put("while", .while_keyword);
        try keywords.put("switch", .switch_keyword);
        try keywords.put("case", .case_keyword);
        try keywords.put("default", .default_keyword);
        try keywords.put("type", .type_keyword);
        try keywords.put("import", .import_keyword);
        try keywords.put("export", .export_keyword);
        try keywords.put("async", .async_keyword);
        try keywords.put("await", .await_keyword);
        try keywords.put("throw", .throw_keyword);
        try keywords.put("catch", .catch_keyword);
        try keywords.put("try", .try_keyword);
        try keywords.put("in", .in_keyword);
        try keywords.put("is", .is_keyword);
        try keywords.put("true", .boolean);
        try keywords.put("false", .boolean);
        try keywords.put("null", .null_literal);
        
        return Lexer{
            .source = source,
            .current = 0,
            .start = 0,
            .line = 1,
            .column = 1,
            .keywords = keywords,
            .arena = arena,
        };
    }
    
    pub fn deinit(self: *Lexer) void {
        self.arena.deinit();
    }
    
    pub fn nextToken(self: *Lexer) LexerError!Token {
        self.skipWhitespace();
        self.start = self.current;
        
        if (self.isAtEnd()) {
            return Token.init(.eof, "", self.getPosition());
        }
        
        const c = self.advance();
        
        if (isAlpha(c)) return self.identifier();
        if (isDigit(c)) return self.number();
        
        return switch (c) {
            '(' => self.makeToken(.left_paren),
            ')' => self.makeToken(.right_paren),
            '{' => self.makeToken(.left_brace),
            '}' => self.makeToken(.right_brace),
            '[' => self.makeToken(.left_bracket),
            ']' => self.makeToken(.right_bracket),
            ';' => self.makeToken(.semicolon),
            ':' => self.makeToken(.colon),
            ',' => self.makeToken(.comma),
            '?' => self.makeToken(.question),
            '@' => self.makeToken(.at_sign),
            '+' => if (self.match('=')) self.makeToken(.plus_assign) else self.makeToken(.plus),
            '*' => if (self.match('=')) self.makeToken(.multiply_assign) else self.makeToken(.multiply),
            '%' => self.makeToken(.modulo),
            '!' => if (self.match('=')) self.makeToken(.not_equal) else self.makeToken(.logical_not),
            '=' => if (self.match('=')) self.makeToken(.equal_equal) else self.makeToken(.assign),
            '<' => if (self.match('=')) self.makeToken(.less_equal) else self.makeToken(.less_than),
            '>' => if (self.match('=')) self.makeToken(.greater_equal) else self.makeToken(.greater_than),
            '&' => if (self.match('&')) self.makeToken(.logical_and) else self.errorToken("Unexpected character"),
            '|' => if (self.match('|')) self.makeToken(.logical_or) else self.errorToken("Unexpected character"),
            '-' => {
                if (self.match('=')) {
                    return self.makeToken(.minus_assign);
                } else if (self.match('>')) {
                    return self.makeToken(.arrow);
                } else {
                    return self.makeToken(.minus);
                }
            },
            '/' => {
                if (self.match('=')) {
                    return self.makeToken(.divide_assign);
                } else if (self.match('/')) {
                    return self.lineComment();
                } else if (self.match('*')) {
                    return self.blockComment();
                } else {
                    return self.makeToken(.divide);
                }
            },
            '"' => self.string(),
            '\n' => {
                const token = self.makeToken(.newline);
                self.line += 1;
                self.column = 1;
                return token;
            },
            else => self.errorToken("Unexpected character"),
        };
    }
    
    fn isAtEnd(self: *Lexer) bool {
        return self.current >= self.source.len;
    }
    
    fn advance(self: *Lexer) u8 {
        if (self.isAtEnd()) return 0;
        const c = self.source[self.current];
        self.current += 1;
        self.column += 1;
        return c;
    }
    
    fn peek(self: *Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }
    
    fn peekNext(self: *Lexer) u8 {
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }
    
    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;
        self.current += 1;
        self.column += 1;
        return true;
    }
    
    fn skipWhitespace(self: *Lexer) void {
        while (!self.isAtEnd()) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => {
                    _ = self.advance();
                },
                else => break,
            }
        }
    }
    
    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }
    
    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }
    
    fn isAlphaNumeric(c: u8) bool {
        return isAlpha(c) or isDigit(c);
    }
    
    fn getPosition(self: *Lexer) Position {
        const token_length = self.current - self.start;
        return Position{
            .line = self.line,
            .column = if (self.column >= token_length) self.column - token_length else 1,
            .offset = self.start,
        };
    }
    
    fn makeToken(self: *Lexer, token_type: TokenType) Token {
        return Token.init(
            token_type,
            self.source[self.start..self.current],
            self.getPosition()
        );
    }
    
    fn errorToken(self: *Lexer, message: []const u8) Token {
        return Token.init(
            .invalid,
            message,
            self.getPosition()
        );
    }
    
    fn identifier(self: *Lexer) Token {
        while (isAlphaNumeric(self.peek())) {
            _ = self.advance();
        }
        
        const text = self.source[self.start..self.current];
        const token_type = self.keywords.get(text) orelse .identifier;
        return self.makeToken(token_type);
    }
    
    fn number(self: *Lexer) LexerError!Token {
        while (isDigit(self.peek())) {
            _ = self.advance();
        }
        
        var is_float = false;
        if (self.peek() == '.' and isDigit(self.peekNext())) {
            is_float = true;
            _ = self.advance();
            while (isDigit(self.peek())) {
                _ = self.advance();
            }
        }
        
        if (self.peek() == 'e' or self.peek() == 'E') {
            is_float = true;
            _ = self.advance();
            if (self.peek() == '+' or self.peek() == '-') {
                _ = self.advance();
            }
            if (!isDigit(self.peek())) {
                return self.errorToken("Invalid number format");
            }
            while (isDigit(self.peek())) {
                _ = self.advance();
            }
        }
        
        return self.makeToken(if (is_float) .float else .integer);
    }
    
    fn string(self: *Lexer) LexerError!Token {
        var has_interpolation = false;
        
        while (self.peek() != '"' and !self.isAtEnd()) {
            if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
                _ = self.advance();
            } else if (self.peek() == '\\') {
                _ = self.advance();
                if (!self.isAtEnd()) {
                    _ = self.advance();
                }
            } else if (self.peek() == '$' and self.peekNext() == '{') {
                has_interpolation = true;
                _ = self.advance();
                _ = self.advance();
                
                var brace_count: u32 = 1;
                while (brace_count > 0 and !self.isAtEnd()) {
                    const c = self.advance();
                    if (c == '{') {
                        brace_count += 1;
                    } else if (c == '}') {
                        brace_count -= 1;
                    } else if (c == '\n') {
                        self.line += 1;
                        self.column = 1;
                    }
                }
            } else {
                const byte = self.peek();
                if (byte & 0x80 != 0) {
                    const remaining_bytes = self.source[self.current..];
                    const utf8_length = unicode.utf8ByteSequenceLength(byte);
                    
                    if (utf8_length == 0 or self.current + utf8_length > self.source.len) {
                        return self.errorToken("Invalid UTF-8 sequence");
                    }
                    
                    const sequence = remaining_bytes[0..utf8_length];
                    if (!unicode.isValidUtf8(sequence)) {
                        return self.errorToken("Invalid UTF-8 sequence");
                    }
                    
                    for (0..utf8_length) |_| {
                        _ = self.advance();
                    }
                } else {
                    _ = self.advance();
                }
            }
        }
        
        if (self.isAtEnd()) {
            return Token.init(.unterminated_string, "Unterminated string", self.getPosition());
        }
        
        _ = self.advance();
        return self.makeToken(.string);
    }
    
    fn lineComment(self: *Lexer) Token {
        while (self.peek() != '\n' and !self.isAtEnd()) {
            _ = self.advance();
        }
        return self.makeToken(.comment);
    }
    
    fn blockComment(self: *Lexer) Token {
        var nesting: u32 = 1;
        
        while (nesting > 0 and !self.isAtEnd()) {
            if (self.peek() == '/' and self.peekNext() == '*') {
                _ = self.advance();
                _ = self.advance();
                nesting += 1;
            } else if (self.peek() == '*' and self.peekNext() == '/') {
                _ = self.advance();
                _ = self.advance();
                nesting -= 1;
            } else if (self.peek() == '\n') {
                self.line += 1;
                self.column = 1;
                _ = self.advance();
            } else {
                _ = self.advance();
            }
        }
        
        return self.makeToken(.comment);
    }
};