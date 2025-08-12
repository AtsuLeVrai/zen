const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Token = lexer.Token;
const TokenType = lexer.TokenType;
const Position = lexer.Position;
const Lexer = lexer.Lexer;
const Expression = ast.Expression;
const Statement = ast.Statement;
const Type = ast.Type;
const Program = ast.Program;
const FunctionDeclaration = ast.FunctionDeclaration;
const Parameter = ast.Parameter;
const AstAllocator = ast.AstAllocator;
const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;
const AssignmentOp = ast.AssignmentOp;
const LiteralValue = ast.LiteralValue;

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    InvalidExpression,
    InvalidStatement,
    InvalidType,
    InvalidFunctionDeclaration,
    OutOfMemory,
    SyntaxError,
};

pub const ErrorInfo = struct {
    message: []const u8,
    position: Position,
    expected: ?[]const TokenType = null,
    actual: TokenType,
};

const Precedence = enum(u8) {
    none = 0,
    assignment = 1,
    logical_or = 2,
    logical_and = 3,
    equality = 4,
    comparison = 5,
    term = 6,
    factor = 7,
    unary = 8,
    call = 9,
    primary = 10,
    
    pub fn next(self: Precedence) Precedence {
        return @enumFromInt(@intFromEnum(self) + 1);
    }
};

const ParseRule = struct {
    prefix: ?*const fn(*Parser) ParseError!*Expression,
    infix: ?*const fn(*Parser, *Expression) ParseError!*Expression,
    precedence: Precedence,
};

pub const Parser = struct {
    lexer: *Lexer,
    current: Token,
    previous: Token,
    had_error: bool,
    panic_mode: bool,
    errors: ArrayList(ErrorInfo),
    ast_allocator: AstAllocator,
    
    const rules = std.EnumArray(TokenType, ParseRule).init(.{
        .integer = ParseRule{ .prefix = number, .infix = null, .precedence = .none },
        .float = ParseRule{ .prefix = number, .infix = null, .precedence = .none },
        .string = ParseRule{ .prefix = string, .infix = null, .precedence = .none },
        .boolean = ParseRule{ .prefix = boolean, .infix = null, .precedence = .none },
        .null_literal = ParseRule{ .prefix = nullLiteral, .infix = null, .precedence = .none },
        .identifier = ParseRule{ .prefix = identifier, .infix = null, .precedence = .none },
        .left_paren = ParseRule{ .prefix = grouping, .infix = call, .precedence = .call },
        .left_bracket = ParseRule{ .prefix = arrayLiteral, .infix = arrayAccess, .precedence = .call },
        .minus = ParseRule{ .prefix = unary, .infix = binary, .precedence = .term },
        .plus = ParseRule{ .prefix = null, .infix = binary, .precedence = .term },
        .multiply = ParseRule{ .prefix = null, .infix = binary, .precedence = .factor },
        .divide = ParseRule{ .prefix = null, .infix = binary, .precedence = .factor },
        .modulo = ParseRule{ .prefix = null, .infix = binary, .precedence = .factor },
        .logical_not = ParseRule{ .prefix = unary, .infix = null, .precedence = .none },
        .equal_equal = ParseRule{ .prefix = null, .infix = binary, .precedence = .equality },
        .not_equal = ParseRule{ .prefix = null, .infix = binary, .precedence = .equality },
        .less_than = ParseRule{ .prefix = null, .infix = binary, .precedence = .comparison },
        .less_equal = ParseRule{ .prefix = null, .infix = binary, .precedence = .comparison },
        .greater_than = ParseRule{ .prefix = null, .infix = binary, .precedence = .comparison },
        .greater_equal = ParseRule{ .prefix = null, .infix = binary, .precedence = .comparison },
        .logical_and = ParseRule{ .prefix = null, .infix = binary, .precedence = .logical_and },
        .logical_or = ParseRule{ .prefix = null, .infix = binary, .precedence = .logical_or },
        .assign = ParseRule{ .prefix = null, .infix = assignment, .precedence = .assignment },
        .plus_assign = ParseRule{ .prefix = null, .infix = assignment, .precedence = .assignment },
        .minus_assign = ParseRule{ .prefix = null, .infix = assignment, .precedence = .assignment },
        .multiply_assign = ParseRule{ .prefix = null, .infix = assignment, .precedence = .assignment },
        .divide_assign = ParseRule{ .prefix = null, .infix = assignment, .precedence = .assignment },
        .comma = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .colon = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .semicolon = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .left_brace = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .right_brace = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .right_paren = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .right_bracket = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .arrow = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .question = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .at_sign = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .eof = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .newline = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .whitespace = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .comment = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .invalid = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .unterminated_string = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .invalid_number = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .func = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .let = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .const_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .return_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .if_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .else_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .for_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .while_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .switch_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .case_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .default_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .type_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .import_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .export_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .async_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .await_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .throw_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .catch_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .try_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .in_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
        .is_keyword = ParseRule{ .prefix = null, .infix = null, .precedence = .none },
    });
    
    pub fn init(allocator: Allocator, lex: *Lexer) Parser {
        return Parser{
            .lexer = lex,
            .current = undefined,
            .previous = undefined,
            .had_error = false,
            .panic_mode = false,
            .errors = ArrayList(ErrorInfo).init(allocator),
            .ast_allocator = AstAllocator.init(allocator),
        };
    }
    
    pub fn deinit(self: *Parser) void {
        self.errors.deinit();
        self.ast_allocator.deinit();
    }
    
    pub fn parse(self: *Parser) ParseError!Program {
        try self.advance();
        
        var functions = ArrayList(FunctionDeclaration).init(self.ast_allocator.allocator());
        defer functions.deinit();
        
        while (!self.isAtEnd()) {
            if (self.match(.func)) {
                const func = try self.functionDeclaration();
                try functions.append(func);
            } else {
                try self.errorAt(self.current, "Expected function declaration");
                try self.advance();
            }
        }
        
        const functions_slice = try self.ast_allocator.allocator().dupe(FunctionDeclaration, functions.items);
        
        return Program{
            .functions = functions_slice,
            .position = Position{ .line = 1, .column = 1, .offset = 0 },
        };
    }
    
    fn functionDeclaration(self: *Parser) ParseError!FunctionDeclaration {
        const func_pos = self.previous.position;
        
        try self.consume(.identifier, "Expected function name");
        const name = self.previous.lexeme;
        
        try self.consume(.left_paren, "Expected '(' after function name");
        
        var parameters = ArrayList(Parameter).init(self.ast_allocator.allocator());
        defer parameters.deinit();
        
        if (!self.check(.right_paren)) {
            while (true) {
                try self.consume(.identifier, "Expected parameter name");
                const param_name = self.previous.lexeme;
                const param_pos = self.previous.position;
                
                try self.consume(.colon, "Expected ':' after parameter name");
                const param_type = try self.parseType();
                
                try parameters.append(Parameter{
                    .name = param_name,
                    .param_type = param_type,
                    .position = param_pos,
                });
                
                if (!self.match(.comma)) break;
            }
        }
        
        try self.consume(.right_paren, "Expected ')' after parameters");
        
        var return_type: ?*Type = null;
        if (self.match(.arrow)) {
            return_type = try self.parseType();
        }
        
        const body = if (self.match(.left_brace)) 
            try self.blockStatement()
        else {
            try self.errorAtCurrent("Expected '{' before function body");
            return ParseError.InvalidFunctionDeclaration;
        };
        
        const parameters_slice = try self.ast_allocator.allocator().dupe(Parameter, parameters.items);
        
        return FunctionDeclaration{
            .name = name,
            .parameters = parameters_slice,
            .return_type = return_type,
            .body = body,
            .position = func_pos,
        };
    }
    
    fn parseType(self: *Parser) ParseError!*Type {
        const pos = self.current.position;
        
        if (self.match(.identifier)) {
            const type_name = self.previous.lexeme;
            const type_kind = self.getTypeKindFromName(type_name);
            
            var base_type = try self.ast_allocator.createType(type_kind, pos);
            if (type_kind == .custom) {
                base_type.name = type_name;
            }
            
            if (self.match(.question)) {
                return try self.ast_allocator.createType(.optional, pos);
            }
            
            if (self.match(.left_bracket)) {
                try self.consume(.right_bracket, "Expected ']' after array type");
                return try self.ast_allocator.createType(.array, pos);
            }
            
            return base_type;
        }
        
        try self.errorAt(self.current, "Expected type");
        return ParseError.InvalidType;
    }
    
    fn getTypeKindFromName(self: *Parser, name: []const u8) ast.TypeKind {
        _ = self;
        if (std.mem.eql(u8, name, "i32")) return .i32;
        if (std.mem.eql(u8, name, "f64")) return .f64;
        if (std.mem.eql(u8, name, "string")) return .string;
        if (std.mem.eql(u8, name, "bool")) return .bool;
        if (std.mem.eql(u8, name, "void")) return .void;
        return .custom;
    }
    
    fn statement(self: *Parser) ParseError!*Statement {
        if (self.match(.let)) return try self.variableDeclaration(false);
        if (self.match(.const_keyword)) return try self.variableDeclaration(true);
        if (self.match(.return_keyword)) return try self.returnStatement();
        if (self.match(.if_keyword)) return try self.ifStatement();
        if (self.match(.while_keyword)) return try self.whileStatement();
        if (self.match(.for_keyword)) return try self.forStatement();
        if (self.match(.switch_keyword)) return try self.switchStatement();
        if (self.match(.left_brace)) return try self.blockStatement();
        
        return try self.expressionStatement();
    }
    
    fn variableDeclaration(self: *Parser, is_const: bool) ParseError!*Statement {
        const decl_pos = self.previous.position;
        
        try self.consume(.identifier, "Expected variable name");
        const name = self.previous.lexeme;
        
        var type_annotation: ?*Type = null;
        if (self.match(.colon)) {
            type_annotation = try self.parseType();
        }
        
        var initializer: ?*Expression = null;
        if (self.match(.assign)) {
            initializer = try self.expression();
        }
        
        try self.consume(.semicolon, "Expected ';' after variable declaration");
        
        return try self.ast_allocator.createVariableDeclaration(
            is_const,
            name,
            type_annotation,
            initializer,
            decl_pos
        );
    }
    
    fn returnStatement(self: *Parser) ParseError!*Statement {
        const return_pos = self.previous.position;
        
        var value: ?*Expression = null;
        if (!self.check(.semicolon) and !self.check(.newline)) {
            value = try self.expression();
        }
        
        try self.consume(.semicolon, "Expected ';' after return statement");
        
        return try self.ast_allocator.createReturnStatement(value, return_pos);
    }
    
    fn ifStatement(self: *Parser) ParseError!*Statement {
        const if_pos = self.previous.position;
        
        try self.consume(.left_paren, "Expected '(' after 'if'");
        const condition = try self.expression();
        try self.consume(.right_paren, "Expected ')' after if condition");
        
        const then_stmt = try self.statement();
        
        var else_stmt: ?*Statement = null;
        if (self.match(.else_keyword)) {
            else_stmt = try self.statement();
        }
        
        return try self.ast_allocator.createIfStatement(condition, then_stmt, else_stmt, if_pos);
    }
    
    fn whileStatement(self: *Parser) ParseError!*Statement {
        const while_pos = self.previous.position;
        
        try self.consume(.left_paren, "Expected '(' after 'while'");
        const condition = try self.expression();
        try self.consume(.right_paren, "Expected ')' after while condition");
        
        const body = try self.statement();
        
        return try self.ast_allocator.createWhileStatement(condition, body, while_pos);
    }
    
    fn forStatement(self: *Parser) ParseError!*Statement {
        const for_pos = self.previous.position;
        
        try self.consume(.left_paren, "Expected '(' after 'for'");
        
        var init_stmt: ?*Statement = null;
        if (self.match(.semicolon)) {
            init_stmt = null;
        } else if (self.match(.let)) {
            init_stmt = try self.variableDeclaration(false);
        } else if (self.match(.const_keyword)) {
            init_stmt = try self.variableDeclaration(true);
        } else {
            init_stmt = try self.expressionStatement();
        }
        
        var condition: ?*Expression = null;
        if (!self.check(.semicolon)) {
            condition = try self.expression();
        }
        try self.consume(.semicolon, "Expected ';' after for loop condition");
        
        var increment: ?*Expression = null;
        if (!self.check(.right_paren)) {
            increment = try self.expression();
        }
        try self.consume(.right_paren, "Expected ')' after for clauses");
        
        const body = try self.statement();
        
        const stmt = try self.ast_allocator.createStatement(.for_statement, for_pos);
        stmt.data = .{ .for_statement = ast.ForStatement{
            .init = init_stmt,
            .condition = condition,
            .increment = increment,
            .body = body,
            .position = for_pos,
        } };
        
        return stmt;
    }
    
    fn switchStatement(self: *Parser) ParseError!*Statement {
        const switch_pos = self.previous.position;
        
        try self.consume(.left_paren, "Expected '(' after 'switch'");
        const switch_expr = try self.expression();
        try self.consume(.right_paren, "Expected ')' after switch expression");
        
        try self.consume(.left_brace, "Expected '{' before switch body");
        
        var cases = ArrayList(ast.SwitchCase).init(self.ast_allocator.allocator());
        defer cases.deinit();
        
        while (!self.check(.right_brace) and !self.isAtEnd()) {
            const case_pos = self.current.position;
            var case_value: ?*Expression = null;
            
            if (self.match(.case_keyword)) {
                case_value = try self.expression();
                try self.consume(.colon, "Expected ':' after case value");
            } else if (self.match(.default_keyword)) {
                try self.consume(.colon, "Expected ':' after 'default'");
            } else {
                try self.errorAt(self.current, "Expected 'case' or 'default'");
                break;
            }
            
            var statements = ArrayList(*Statement).init(self.ast_allocator.allocator());
            defer statements.deinit();
            
            while (!self.check(.case_keyword) and !self.check(.default_keyword) and !self.check(.right_brace) and !self.isAtEnd()) {
                try statements.append(try self.statement());
            }
            
            const statements_slice = try self.ast_allocator.allocator().dupe(*Statement, statements.items);
            
            try cases.append(ast.SwitchCase{
                .value = case_value,
                .statements = statements_slice,
                .position = case_pos,
            });
        }
        
        try self.consume(.right_brace, "Expected '}' after switch body");
        
        const cases_slice = try self.ast_allocator.allocator().dupe(ast.SwitchCase, cases.items);
        
        const stmt = try self.ast_allocator.createStatement(.switch_statement, switch_pos);
        stmt.data = .{ .switch_statement = ast.SwitchStatement{
            .expression = switch_expr,
            .cases = cases_slice,
            .position = switch_pos,
        } };
        
        return stmt;
    }
    
    fn blockStatement(self: *Parser) ParseError!*Statement {
        const block_pos = self.previous.position;
        
        var statements = ArrayList(*Statement).init(self.ast_allocator.allocator());
        defer statements.deinit();
        
        while (!self.check(.right_brace) and !self.isAtEnd()) {
            self.skipStatementSeparators();
            if (self.check(.right_brace)) break;
            
            try statements.append(try self.statement());
        }
        
        try self.consume(.right_brace, "Expected '}' after block");
        
        const statements_slice = try self.ast_allocator.allocator().dupe(*Statement, statements.items);
        
        return try self.ast_allocator.createBlockStatement(statements_slice, block_pos);
    }
    
    fn skipStatementSeparators(self: *Parser) void {
        while (!self.isAtEnd() and (self.check(.newline) or self.check(.whitespace) or self.check(.comment))) {
            self.advance() catch break;
        }
    }
    
    fn expressionStatement(self: *Parser) ParseError!*Statement {
        const expr = try self.expression();
        try self.consume(.semicolon, "Expected ';' after expression");
        return try self.ast_allocator.createExpressionStatement(expr);
    }
    
    pub fn expression(self: *Parser) ParseError!*Expression {
        return try self.parsePrecedence(.assignment);
    }
    
    fn parsePrecedence(self: *Parser, precedence: Precedence) ParseError!*Expression {
        try self.advance();
        
        const prefix_rule = rules.get(self.previous.type).prefix orelse {
            try self.errorAt(self.previous, "Expected expression");
            return ParseError.InvalidExpression;
        };
        
        var expr = try prefix_rule(self);
        
        while (@intFromEnum(precedence) <= @intFromEnum(rules.get(self.current.type).precedence)) {
            try self.advance();
            const infix_rule = rules.get(self.previous.type).infix.?;
            expr = try infix_rule(self, expr);
        }
        
        return expr;
    }
    
    fn number(self: *Parser) ParseError!*Expression {
        const pos = self.previous.position;
        const lexeme = self.previous.lexeme;
        
        if (self.previous.type == .integer) {
            const value = std.fmt.parseInt(i64, lexeme, 10) catch {
                try self.errorAt(self.previous, "Invalid integer literal");
                return ParseError.InvalidExpression;
            };
            return try self.ast_allocator.createLiteralExpression(
                LiteralValue{ .integer = value },
                pos
            );
        } else {
            const value = std.fmt.parseFloat(f64, lexeme) catch {
                try self.errorAt(self.previous, "Invalid float literal");
                return ParseError.InvalidExpression;
            };
            return try self.ast_allocator.createLiteralExpression(
                LiteralValue{ .float = value },
                pos
            );
        }
    }
    
    fn string(self: *Parser) ParseError!*Expression {
        const pos = self.previous.position;
        var lexeme = self.previous.lexeme;
        
        if (lexeme.len >= 2 and lexeme[0] == '"' and lexeme[lexeme.len - 1] == '"') {
            lexeme = lexeme[1 .. lexeme.len - 1];
        }
        
        return try self.ast_allocator.createLiteralExpression(
            LiteralValue{ .string = lexeme },
            pos
        );
    }
    
    fn boolean(self: *Parser) ParseError!*Expression {
        const pos = self.previous.position;
        const value = std.mem.eql(u8, self.previous.lexeme, "true");
        
        return try self.ast_allocator.createLiteralExpression(
            LiteralValue{ .boolean = value },
            pos
        );
    }
    
    fn nullLiteral(self: *Parser) ParseError!*Expression {
        const pos = self.previous.position;
        
        return try self.ast_allocator.createLiteralExpression(
            LiteralValue{ .null_value = {} },
            pos
        );
    }
    
    fn identifier(self: *Parser) ParseError!*Expression {
        const pos = self.previous.position;
        const name = self.previous.lexeme;
        
        return try self.ast_allocator.createIdentifierExpression(name, pos);
    }
    
    fn grouping(self: *Parser) ParseError!*Expression {
        const expr = try self.expression();
        try self.consume(.right_paren, "Expected ')' after expression");
        return expr;
    }
    
    fn arrayLiteral(self: *Parser) ParseError!*Expression {
        const pos = self.previous.position;
        
        var elements = ArrayList(*Expression).init(self.ast_allocator.allocator());
        defer elements.deinit();
        
        if (!self.check(.right_bracket)) {
            while (true) {
                try elements.append(try self.expression());
                if (!self.match(.comma)) break;
            }
        }
        
        try self.consume(.right_bracket, "Expected ']' after array elements");
        
        const elements_slice = try self.ast_allocator.allocator().dupe(*Expression, elements.items);
        return try self.ast_allocator.createArrayLiteralExpression(elements_slice, pos);
    }
    
    fn call(self: *Parser, callee: *Expression) ParseError!*Expression {
        const pos = self.previous.position;
        
        var arguments = ArrayList(*Expression).init(self.ast_allocator.allocator());
        defer arguments.deinit();
        
        if (!self.check(.right_paren)) {
            while (true) {
                try arguments.append(try self.expression());
                if (!self.match(.comma)) break;
            }
        }
        
        try self.consume(.right_paren, "Expected ')' after arguments");
        
        const arguments_slice = try self.ast_allocator.allocator().dupe(*Expression, arguments.items);
        return try self.ast_allocator.createCallExpression(callee, arguments_slice, pos);
    }
    
    fn arrayAccess(self: *Parser, array: *Expression) ParseError!*Expression {
        const pos = self.previous.position;
        const index = try self.expression();
        try self.consume(.right_bracket, "Expected ']' after array index");
        
        return try self.ast_allocator.createArrayAccessExpression(array, index, pos);
    }
    
    fn unary(self: *Parser) ParseError!*Expression {
        const pos = self.previous.position;
        const operator_type = self.previous.type;
        
        const operand = try self.parsePrecedence(.unary);
        
        const op: UnaryOp = switch (operator_type) {
            .minus => .minus,
            .logical_not => .logical_not,
            else => {
                try self.errorAt(self.previous, "Invalid unary operator");
                return ParseError.InvalidExpression;
            },
        };
        
        return try self.ast_allocator.createUnaryExpression(op, operand, pos);
    }
    
    fn binary(self: *Parser, left: *Expression) ParseError!*Expression {
        const pos = self.previous.position;
        const operator_type = self.previous.type;
        const rule = rules.get(operator_type);
        
        const right = try self.parsePrecedence(rule.precedence.next());
        
        const op: BinaryOp = switch (operator_type) {
            .plus => .add,
            .minus => .subtract,
            .multiply => .multiply,
            .divide => .divide,
            .modulo => .modulo,
            .equal_equal => .equal,
            .not_equal => .not_equal,
            .less_than => .less_than,
            .less_equal => .less_equal,
            .greater_than => .greater_than,
            .greater_equal => .greater_equal,
            .logical_and => .logical_and,
            .logical_or => .logical_or,
            else => {
                try self.errorAt(self.previous, "Invalid binary operator");
                return ParseError.InvalidExpression;
            },
        };
        
        return try self.ast_allocator.createBinaryExpression(left, op, right, pos);
    }
    
    fn assignment(self: *Parser, target: *Expression) ParseError!*Expression {
        const pos = self.previous.position;
        const operator_type = self.previous.type;
        
        const value = try self.parsePrecedence(.assignment);
        
        const op: AssignmentOp = switch (operator_type) {
            .assign => .assign,
            .plus_assign => .add_assign,
            .minus_assign => .subtract_assign,
            .multiply_assign => .multiply_assign,
            .divide_assign => .divide_assign,
            else => {
                try self.errorAt(self.previous, "Invalid assignment operator");
                return ParseError.InvalidExpression;
            },
        };
        
        return try self.ast_allocator.createAssignmentExpression(target, op, value, pos);
    }
    
    pub fn advance(self: *Parser) ParseError!void {
        self.previous = self.current;
        
        while (true) {
            self.current = self.lexer.nextToken() catch |err| {
                switch (err) {
                    lexer.LexerError.UnterminatedString => {
                        try self.errorAt(self.current, "Unterminated string");
                        return ParseError.SyntaxError;
                    },
                    lexer.LexerError.InvalidNumber => {
                        try self.errorAt(self.current, "Invalid number format");
                        return ParseError.SyntaxError;
                    },
                    lexer.LexerError.InvalidCharacter => {
                        try self.errorAt(self.current, "Invalid character");
                        return ParseError.SyntaxError;
                    },
                    lexer.LexerError.OutOfMemory => return ParseError.OutOfMemory,
                }
            };
            
            if (self.current.type != .invalid) break;
            
            try self.errorAtCurrent("Invalid token");
        }
    }
    
    fn isAtEnd(self: *Parser) bool {
        return self.current.type == .eof;
    }
    
    fn check(self: *Parser, token_type: TokenType) bool {
        return self.current.type == token_type;
    }
    
    pub fn match(self: *Parser, token_type: TokenType) bool {
        if (!self.check(token_type)) return false;
        self.advance() catch return false;
        return true;
    }
    
    fn consume(self: *Parser, token_type: TokenType, message: []const u8) ParseError!void {
        if (self.current.type == token_type) {
            try self.advance();
            return;
        }
        
        try self.errorAtCurrent(message);
    }
    
    fn errorAtCurrent(self: *Parser, message: []const u8) ParseError!void {
        try self.errorAt(self.current, message);
    }
    
    fn errorAt(self: *Parser, token: Token, message: []const u8) ParseError!void {
        if (self.panic_mode) return;
        self.panic_mode = true;
        self.had_error = true;
        
        try self.errors.append(ErrorInfo{
            .message = message,
            .position = token.position,
            .actual = token.type,
        });
    }
    
    fn synchronize(self: *Parser) void {
        self.panic_mode = false;
        
        while (self.current.type != .eof) {
            if (self.previous.type == .semicolon) return;
            
            switch (self.current.type) {
                .func,
                .let,
                .const_keyword,
                .if_keyword,
                .while_keyword,
                .for_keyword,
                .return_keyword,
                .switch_keyword => return,
                else => {},
            }
            
            self.advance() catch return;
        }
    }
};