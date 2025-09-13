const std = @import("std");
const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const types = @import("types.zig");

const Token = lexer.Token;
const TokenType = lexer.TokenType;

pub const ParseError = error{
    UnexpectedToken,
    ExpectedExpression,
    ExpectedStatement,
    ExpectedIdentifier,
    ExpectedType,
    OutOfMemory,
};

pub const Parser = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    tokens: []Token,
    current: usize,

    pub fn init(allocator: std.mem.Allocator, tokens: []Token) Self {
        return Self{
            .allocator = allocator,
            .tokens = tokens,
            .current = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        _ = self;
    }

    pub fn parseProgram(self: *Self) !*ast.Node {
        var statements = std.ArrayList(*ast.Node){};
        defer statements.deinit(self.allocator);

        while (!self.isAtEnd()) {
            if (self.check(.eof)) break;
            const stmt = try self.declaration();
            try statements.append(self.allocator,stmt);
        }

        return ast.createProgram(self.allocator, try statements.toOwnedSlice(self.allocator));
    }

    fn declaration(self: *Self) ParseError!*ast.Node {
        if (self.match(.fn_)) return self.functionDeclaration();
        if (self.match(.const_)) return self.variableDeclaration(false);
        if (self.match(.let_)) return self.variableDeclaration(true);
        return self.statement();
    }

    fn functionDeclaration(self: *Self) ParseError!*ast.Node {
        const name_token = try self.consume(.identifier, "Expected function name");
        const name = name_token.lexeme;

        _ = try self.consume(.left_paren, "Expected '(' after function name");

        var parameters = std.ArrayList(ast.Parameter){};
        defer parameters.deinit(self.allocator);

        if (!self.check(.right_paren)) {
            while (true) {
                const param_name_token = try self.consume(.identifier, "Expected parameter name");
                _ = try self.consume(.colon, "Expected ':' after parameter name");
                const param_type = try self.parseType();

                try parameters.append(self.allocator,ast.Parameter{
                    .name = param_name_token.lexeme,
                    .param_type = param_type,
                });

                if (!self.match(.comma)) break;
            }
        }

        _ = try self.consume(.right_paren, "Expected ')' after parameters");
        _ = try self.consume(.arrow, "Expected '->' after parameters");
        const return_type = try self.parseType();

        _ = try self.consume(.left_brace, "Expected '{' before function body");
        const body = try self.blockStatement();

        return ast.createFunctionDeclaration(
            self.allocator,
            getPosition(name_token),
            name,
            try parameters.toOwnedSlice(self.allocator),
            return_type,
            body,
        );
    }

    fn variableDeclaration(self: *Self, is_mutable: bool) ParseError!*ast.Node {
        const name_token = try self.consume(.identifier, "Expected variable name");

        var var_type: ?types.Type = null;
        if (self.match(.colon)) {
            var_type = try self.parseType();
        }

        var initializer: ?*ast.Node = null;
        if (self.match(.equal)) {
            initializer = try self.expression();
        }

        _ = try self.consume(.semicolon, "Expected ';' after variable declaration");

        const node = try ast.createNode(self.allocator, .variable_declaration, getPosition(name_token));
        node.data = .{ .variable_declaration = ast.VariableDeclaration{
            .name = name_token.lexeme,
            .var_type = var_type,
            .is_mutable = is_mutable,
            .initializer = initializer,
        } };
        return node;
    }

    fn statement(self: *Self) ParseError!*ast.Node {
        if (self.match(.if_)) return self.ifStatement();
        if (self.match(.while_)) return self.whileStatement();
        if (self.match(.return_)) return self.returnStatement();
        if (self.match(.left_brace)) return self.blockStatement();
        return self.expressionStatement();
    }

    fn ifStatement(self: *Self) ParseError!*ast.Node {
        _ = try self.consume(.left_paren, "Expected '(' after 'if'");
        const condition = try self.expression();
        _ = try self.consume(.right_paren, "Expected ')' after if condition");

        const then_branch = try self.statement();
        var else_branch: ?*ast.Node = null;
        if (self.match(.else_)) {
            else_branch = try self.statement();
        }

        const node = try ast.createNode(self.allocator, .if_statement, getPosition(self.previous()));
        node.data = .{ .if_statement = ast.IfStatement{
            .condition = condition,
            .then_branch = then_branch,
            .else_branch = else_branch,
        } };
        return node;
    }

    fn whileStatement(self: *Self) ParseError!*ast.Node {
        _ = try self.consume(.left_paren, "Expected '(' after 'while'");
        const condition = try self.expression();
        _ = try self.consume(.right_paren, "Expected ')' after while condition");

        const body = try self.statement();

        const node = try ast.createNode(self.allocator, .while_statement, getPosition(self.previous()));
        node.data = .{ .while_statement = ast.WhileStatement{
            .condition = condition,
            .body = body,
        } };
        return node;
    }

    fn returnStatement(self: *Self) ParseError!*ast.Node {
        const keyword = self.previous();
        var value: ?*ast.Node = null;

        if (!self.check(.semicolon)) {
            value = try self.expression();
        }

        _ = try self.consume(.semicolon, "Expected ';' after return value");

        const node = try ast.createNode(self.allocator, .return_statement, getPosition(keyword));
        node.data = .{ .return_statement = ast.ReturnStatement{ .value = value } };
        return node;
    }

    fn blockStatement(self: *Self) ParseError!*ast.Node {
        var statements = std.ArrayList(*ast.Node){};
        defer statements.deinit(self.allocator);

        while (!self.check(.right_brace) and !self.isAtEnd()) {
            try statements.append(self.allocator,try self.declaration());
        }

        _ = try self.consume(.right_brace, "Expected '}' after block");

        const node = try ast.createNode(self.allocator, .block_statement, getPosition(self.previous()));
        node.data = .{ .block_statement = ast.BlockStatement{
            .statements = try statements.toOwnedSlice(self.allocator),
        } };
        return node;
    }

    fn expressionStatement(self: *Self) ParseError!*ast.Node {
        const expr = try self.expression();
        _ = try self.consume(.semicolon, "Expected ';' after expression");

        const node = try ast.createNode(self.allocator, .expression_statement, getPosition(self.previous()));
        node.data = .{ .expression_statement = ast.ExpressionStatement{ .expression = expr } };
        return node;
    }

    fn expression(self: *Self) ParseError!*ast.Node {
        return self.assignment();
    }

    fn assignment(self: *Self) ParseError!*ast.Node {
        const expr = try self.logicalOr();

        if (self.match(.equal)) {
            const value = try self.assignment();
            if (expr.node_type == .identifier) {
                const node = try ast.createNode(self.allocator, .assignment_expression, getPosition(self.previous()));
                node.data = .{ .assignment_expression = ast.AssignmentExpression{
                    .target = expr,
                    .value = value,
                } };
                return node;
            }
            return ParseError.ExpectedExpression;
        }

        return expr;
    }

    fn logicalOr(self: *Self) ParseError!*ast.Node {
        var expr = try self.logicalAnd();

        while (self.match(.equal_equal)) { // Using == as OR for now, add proper || later
            const operator: ast.BinaryOperator = .logical_or;
            const right = try self.logicalAnd();
            const node = try ast.createNode(self.allocator, .binary_expression, getPosition(self.previous()));
            node.data = .{ .binary_expression = ast.BinaryExpression{
                .left = expr,
                .operator = operator,
                .right = right,
            } };
            expr = node;
        }

        return expr;
    }

    fn logicalAnd(self: *Self) ParseError!*ast.Node {
        const expr = try self.equality();

        // Add && support later
        return expr;
    }

    fn equality(self: *Self) ParseError!*ast.Node {
        var expr = try self.comparison();

        while (self.match(.bang_equal) or self.match(.equal_equal)) {
            const operator: ast.BinaryOperator = if (self.previous().type == .bang_equal) .not_equal else .equal;
            const right = try self.comparison();
            const node = try ast.createNode(self.allocator, .binary_expression, getPosition(self.previous()));
            node.data = .{ .binary_expression = ast.BinaryExpression{
                .left = expr,
                .operator = operator,
                .right = right,
            } };
            expr = node;
        }

        return expr;
    }

    fn comparison(self: *Self) ParseError!*ast.Node {
        var expr = try self.term();

        while (self.match(.greater) or self.match(.greater_equal) or self.match(.less) or self.match(.less_equal)) {
            const operator: ast.BinaryOperator = switch (self.previous().type) {
                .greater => .greater_than,
                .greater_equal => .greater_equal,
                .less => .less_than,
                .less_equal => .less_equal,
                else => unreachable,
            };
            const right = try self.term();
            const node = try ast.createNode(self.allocator, .binary_expression, getPosition(self.previous()));
            node.data = .{ .binary_expression = ast.BinaryExpression{
                .left = expr,
                .operator = operator,
                .right = right,
            } };
            expr = node;
        }

        return expr;
    }

    fn term(self: *Self) ParseError!*ast.Node {
        var expr = try self.factor();

        while (self.match(.minus) or self.match(.plus)) {
            const operator: ast.BinaryOperator = if (self.previous().type == .minus) .subtract else .add;
            const right = try self.factor();
            const node = try ast.createNode(self.allocator, .binary_expression, getPosition(self.previous()));
            node.data = .{ .binary_expression = ast.BinaryExpression{
                .left = expr,
                .operator = operator,
                .right = right,
            } };
            expr = node;
        }

        return expr;
    }

    fn factor(self: *Self) ParseError!*ast.Node {
        var expr = try self.unary();

        while (self.match(.slash) or self.match(.star)) {
            const operator: ast.BinaryOperator = if (self.previous().type == .slash) .divide else .multiply;
            const right = try self.unary();
            const node = try ast.createNode(self.allocator, .binary_expression, getPosition(self.previous()));
            node.data = .{ .binary_expression = ast.BinaryExpression{
                .left = expr,
                .operator = operator,
                .right = right,
            } };
            expr = node;
        }

        return expr;
    }

    fn unary(self: *Self) ParseError!*ast.Node {
        if (self.match(.bang) or self.match(.minus)) {
            const operator: ast.UnaryOperator = if (self.previous().type == .bang) .logical_not else .minus;
            const right = try self.unary();
            const node = try ast.createNode(self.allocator, .unary_expression, getPosition(self.previous()));
            node.data = .{ .unary_expression = ast.UnaryExpression{
                .operator = operator,
                .operand = right,
            } };
            return node;
        }

        return self.call();
    }

    fn call(self: *Self) ParseError!*ast.Node {
        var expr = try self.primary();

        while (true) {
            if (self.match(.left_paren)) {
                expr = try self.finishCall(expr);
            } else {
                break;
            }
        }

        return expr;
    }

    fn finishCall(self: *Self, callee: *ast.Node) ParseError!*ast.Node {
        var arguments = std.ArrayList(*ast.Node){};
        defer arguments.deinit(self.allocator);

        if (!self.check(.right_paren)) {
            while (true) {
                try arguments.append(self.allocator,try self.expression());
                if (!self.match(.comma)) break;
            }
        }

        _ = try self.consume(.right_paren, "Expected ')' after arguments");

        const node = try ast.createNode(self.allocator, .call_expression, getPosition(self.previous()));
        node.data = .{ .call_expression = ast.CallExpression{
            .function = callee,
            .arguments = try arguments.toOwnedSlice(self.allocator),
        } };
        return node;
    }

    fn primary(self: *Self) ParseError!*ast.Node {
        if (self.match(.false_)) {
            const node = try ast.createNode(self.allocator, .boolean_literal, getPosition(self.previous()));
            node.data = .{ .boolean_literal = ast.BooleanLiteral{ .value = false } };
            return node;
        }

        if (self.match(.true_)) {
            const node = try ast.createNode(self.allocator, .boolean_literal, getPosition(self.previous()));
            node.data = .{ .boolean_literal = ast.BooleanLiteral{ .value = true } };
            return node;
        }

        if (self.match(.number)) {
            const lexeme = self.previous().lexeme;
            const value = std.fmt.parseFloat(f64, lexeme) catch return ParseError.ExpectedExpression;
            const is_integer = std.mem.indexOf(u8, lexeme, ".") == null;
            return ast.createNumberLiteral(self.allocator, getPosition(self.previous()), value, is_integer);
        }

        if (self.match(.string_literal)) {
            const node = try ast.createNode(self.allocator, .string_literal, getPosition(self.previous()));
            node.data = .{ .string_literal = ast.StringLiteral{ .value = self.previous().lexeme } };
            return node;
        }

        if (self.match(.identifier)) {
            return ast.createIdentifier(self.allocator, getPosition(self.previous()), self.previous().lexeme);
        }

        if (self.match(.left_paren)) {
            const expr = try self.expression();
            _ = try self.consume(.right_paren, "Expected ')' after expression");
            return expr;
        }

        return ParseError.ExpectedExpression;
    }

    fn parseType(self: *Self) ParseError!types.Type {
        if (self.match(.void)) return .void;
        if (self.match(.i32)) return .i32;
        if (self.match(.f64)) return .f64;
        if (self.match(.bool)) return .bool;
        if (self.match(.string)) return .string;
        return ParseError.ExpectedType;
    }

    // Utility methods
    fn match(self: *Self, token_type: TokenType) bool {
        if (self.check(token_type)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn check(self: *Self, token_type: TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().type == token_type;
    }

    fn advance(self: *Self) Token {
        if (!self.isAtEnd()) self.current += 1;
        return self.previous();
    }

    fn isAtEnd(self: *Self) bool {
        return self.peek().type == .eof;
    }

    fn peek(self: *Self) Token {
        return self.tokens[self.current];
    }

    fn previous(self: *Self) Token {
        return self.tokens[self.current - 1];
    }

    fn consume(self: *Self, token_type: TokenType, message: []const u8) ParseError!Token {
        if (self.check(token_type)) return self.advance();

        std.debug.print("Parse error: {s} at token '{s}'\n", .{ message, self.peek().lexeme });
        return ParseError.UnexpectedToken;
    }
};

// Token helper method
fn tokenGetPosition(token: Token) ast.Position {
    return ast.Position{ .line = token.line, .column = token.column };
}

// Add method to Token type (this is a workaround since we can't extend the Token struct directly)
const TokenExtensions = struct {
    fn getPosition(token: Token) ast.Position {
        return ast.Position{ .line = token.line, .column = token.column };
    }
};

// Make the extension available
pub fn getPosition(token: Token) ast.Position {
    return TokenExtensions.getPosition(token);
}
