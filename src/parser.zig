const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const lexer = @import("lexer.zig");
const ast = @import("ast.zig");
const errors = @import("errors.zig");

const Token = lexer.Token;
const TokenType = lexer.TokenType;
const AST = ast.AST;
const Node = ast.Node;
const NodeId = ast.NodeId;
const NodeBuilder = ast.NodeBuilder;
const ZenType = ast.ZenType;
const SourceSpan = errors.SourceSpan;
const ZenError = errors.ZenError;

pub const Parser = struct {
    allocator: Allocator,
    tokens: []Token,
    current: usize,
    filename: []const u8,
    ast: AST,
    builder: NodeBuilder,

    pub fn init(allocator: Allocator, tokens: []Token, filename: []const u8) Parser {
        var ast_instance = AST.init(allocator);
        const builder = NodeBuilder.init(&ast_instance);

        return Parser{
            .allocator = allocator,
            .tokens = tokens,
            .current = 0,
            .filename = filename,
            .ast = ast_instance,
            .builder = builder,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.ast.deinit();
    }

    pub fn parse(self: *Parser) ZenError!*AST {
        const program_id = try self.parseProgram();
        self.ast.setRoot(program_id);
        return &self.ast;
    }

    fn parseProgram(self: *Parser) ZenError!NodeId {
        var declarations = ArrayList(NodeId).init(self.allocator);
        defer declarations.deinit();

        while (!self.isAtEnd()) {
            // Skip newlines and comments at top level
            if (self.check(.newline) or self.check(.comment)) {
                _ = self.advance();
                continue;
            }

            const decl = try self.parseDeclaration();
            try declarations.append(decl);
        }

        const span = if (self.tokens.len > 0)
            self.tokens[0].span
        else
            SourceSpan.init(errors.Position.init(0, 0, 0), errors.Position.init(0, 0, 0), self.filename);

        return self.builder.createProgram(span, try declarations.toOwnedSlice());
    }

    fn parseDeclaration(self: *Parser) ZenError!NodeId {
        if (self.match(.func)) return self.parseFunctionDeclaration();
        if (self.match(.let) or self.match(.const_kw)) return self.parseVariableDeclaration();
        if (self.match(.type_kw)) return self.parseTypeDeclaration();
        if (self.match(.import_kw)) return self.parseImportDeclaration();
        if (self.match(.export_kw)) return self.parseExportDeclaration();

        return self.parseStatement();
    }

    fn parseFunctionDeclaration(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;

        // Parse async modifier
        const is_async = if (self.check(.async_kw)) blk: {
            _ = self.advance();
            break :blk true;
        } else false;

        // Parse function name
        if (!self.check(.identifier)) {
            return ZenError.UnexpectedToken;
        }
        const name = self.advance().lexeme;

        // Parse parameters
        _ = try self.consume(.left_paren, "Expected '(' after function name");
        var params = ArrayList(ast.FunctionDecl.Parameter).init(self.allocator);
        defer params.deinit();

        if (!self.check(.right_paren)) {
            while (true) {
                const param_name_token = try self.consume(.identifier, "Expected parameter name");
                _ = try self.consume(.colon, "Expected ':' after parameter name");
                const param_type = try self.parseType();

                const param = ast.FunctionDecl.Parameter{
                    .name = param_name_token.lexeme,
                    .param_type = param_type,
                    .span = param_name_token.span,
                };
                try params.append(param);

                if (!self.match(.comma)) break;
            }
        }
        _ = try self.consume(.right_paren, "Expected ')' after parameters");

        // Parse return type
        var return_type: ?ZenType = null;
        if (self.match(.arrow)) {
            return_type = try self.parseType();
        }

        // Parse annotations (simplified for now)
        var annotations = ArrayList(ast.Annotation).init(self.allocator);
        defer annotations.deinit();

        // Parse body
        _ = try self.consume(.left_brace, "Expected '{' before function body");
        const body = try self.parseBlockStatement();

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        return self.builder.createFunction(span, name, try params.toOwnedSlice(), return_type, body, is_async, try annotations.toOwnedSlice());
    }

    fn parseVariableDeclaration(self: *Parser) ZenError!NodeId {
        const is_const = self.previous().type == .const_kw;
        const start_span = self.previous().span;

        const name_token = try self.consume(.identifier, "Expected variable name");
        const name = name_token.lexeme;

        var var_type: ?ZenType = null;
        if (self.match(.colon)) {
            var_type = try self.parseType();
        }

        var initializer: ?NodeId = null;
        if (self.match(.assign)) {
            initializer = try self.parseExpression();
        }

        try self.consumeStatementEnd();

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const var_decl = ast.VariableDecl{
            .name = name,
            .var_type = var_type,
            .initializer = initializer,
            .is_const = is_const,
        };

        return self.ast.addNode(span, .{ .variable_decl = var_decl });
    }

    fn parseTypeDeclaration(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;

        const name_token = try self.consume(.identifier, "Expected type name");
        _ = try self.consume(.assign, "Expected '=' after type name");
        _ = try self.consume(.left_brace, "Expected '{' to start type definition");

        var fields = ArrayList(ast.TypeDecl.Field).init(self.allocator);
        defer fields.deinit();

        while (!self.check(.right_brace) and !self.isAtEnd()) {
            if (self.match(.newline) or self.match(.comment)) continue;

            const field_name_token = try self.consume(.identifier, "Expected field name");
            _ = try self.consume(.colon, "Expected ':' after field name");
            const field_type = try self.parseType();

            if (self.match(.comma)) {} // Optional comma

            const field = ast.TypeDecl.Field{
                .name = field_name_token.lexeme,
                .field_type = field_type,
                .span = field_name_token.span,
            };
            try fields.append(field);
        }

        _ = try self.consume(.right_brace, "Expected '}' after type definition");

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const type_decl = ast.TypeDecl{
            .name = name_token.lexeme,
            .fields = try fields.toOwnedSlice(),
        };

        return self.ast.addNode(span, .{ .type_decl = type_decl });
    }

    fn parseImportDeclaration(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;

        _ = try self.consume(.left_brace, "Expected '{' after import");

        var items = ArrayList(ast.ImportDecl.ImportItem).init(self.allocator);
        defer items.deinit();

        while (!self.check(.right_brace) and !self.isAtEnd()) {
            const name_token = try self.consume(.identifier, "Expected import item name");
            const alias: ?[]const u8 = null;

            // Handle 'as' alias (simplified - we don't have 'as' token yet)

            const item = ast.ImportDecl.ImportItem{
                .name = name_token.lexeme,
                .alias = alias,
            };
            try items.append(item);

            if (!self.match(.comma)) break;
        }

        _ = try self.consume(.right_brace, "Expected '}' after import items");
        _ = try self.consume(.identifier, "Expected 'from' keyword"); // Should be 'from'
        const path_token = try self.consume(.string, "Expected import path");

        try self.consumeStatementEnd();

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const import_decl = ast.ImportDecl{
            .path = path_token.lexeme,
            .items = try items.toOwnedSlice(),
        };

        return self.ast.addNode(span, .{ .import_decl = import_decl });
    }

    fn parseExportDeclaration(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;
        const declaration = try self.parseDeclaration();

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const export_decl = ast.ExportDecl{
            .declaration = declaration,
        };

        return self.ast.addNode(span, .{ .export_decl = export_decl });
    }

    fn parseStatement(self: *Parser) ZenError!NodeId {
        if (self.match(.if_kw)) return self.parseIfStatement();
        if (self.match(.while_kw)) return self.parseWhileStatement();
        if (self.match(.for_kw)) return self.parseForStatement();
        if (self.match(.return_kw)) return self.parseReturnStatement();
        if (self.match(.throw_kw)) return self.parseThrowStatement();
        if (self.match(.left_brace)) return self.parseBlockStatement();

        return self.parseExpressionStatement();
    }

    fn parseIfStatement(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;

        _ = try self.consume(.left_paren, "Expected '(' after 'if'");
        const condition = try self.parseExpression();
        _ = try self.consume(.right_paren, "Expected ')' after if condition");

        const then_stmt = try self.parseStatement();

        var else_stmt: ?NodeId = null;
        if (self.match(.else_kw)) {
            else_stmt = try self.parseStatement();
        }

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const if_stmt = ast.IfStmt{
            .condition = condition,
            .then_stmt = then_stmt,
            .else_stmt = else_stmt,
        };

        return self.ast.addNode(span, .{ .if_stmt = if_stmt });
    }

    fn parseWhileStatement(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;

        _ = try self.consume(.left_paren, "Expected '(' after 'while'");
        const condition = try self.parseExpression();
        _ = try self.consume(.right_paren, "Expected ')' after while condition");

        const body = try self.parseStatement();

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const while_stmt = ast.WhileStmt{
            .condition = condition,
            .body = body,
        };

        return self.ast.addNode(span, .{ .while_stmt = while_stmt });
    }

    fn parseForStatement(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;

        _ = try self.consume(.left_paren, "Expected '(' after 'for'");
        const variable_token = try self.consume(.identifier, "Expected variable name");
        _ = try self.consume(.in_kw, "Expected 'in' after for variable");
        const iterable = try self.parseExpression();
        _ = try self.consume(.right_paren, "Expected ')' after for clause");

        const body = try self.parseStatement();

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const for_stmt = ast.ForStmt{
            .variable = variable_token.lexeme,
            .iterable = iterable,
            .body = body,
        };

        return self.ast.addNode(span, .{ .for_stmt = for_stmt });
    }

    fn parseReturnStatement(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;

        var value: ?NodeId = null;
        if (!self.check(.semicolon) and !self.check(.newline) and !self.isAtEnd()) {
            value = try self.parseExpression();
        }

        try self.consumeStatementEnd();

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const return_stmt = ast.ReturnStmt{
            .value = value,
        };

        return self.ast.addNode(span, .{ .return_stmt = return_stmt });
    }

    fn parseThrowStatement(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;

        const expression = try self.parseExpression();
        try self.consumeStatementEnd();

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const throw_stmt = ast.ThrowStmt{
            .expression = expression,
        };

        return self.ast.addNode(span, .{ .throw_stmt = throw_stmt });
    }

    fn parseBlockStatement(self: *Parser) ZenError!NodeId {
        const start_span = self.previous().span;

        var statements = ArrayList(NodeId).init(self.allocator);
        defer statements.deinit();

        while (!self.check(.right_brace) and !self.isAtEnd()) {
            if (self.match(.newline) or self.match(.comment)) continue;

            const stmt = try self.parseStatement();
            try statements.append(stmt);
        }

        _ = try self.consume(.right_brace, "Expected '}' after block");

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        return self.builder.createBlock(span, try statements.toOwnedSlice());
    }

    fn parseExpressionStatement(self: *Parser) ZenError!NodeId {
        const start_span = self.peek().span;
        const expression = try self.parseExpression();
        try self.consumeStatementEnd();

        const end_span = self.previous().span;
        const span = SourceSpan.init(start_span.start, end_span.end, self.filename);

        const expr_stmt = ast.ExpressionStmt{
            .expression = expression,
        };

        return self.ast.addNode(span, .{ .expression_stmt = expr_stmt });
    }

    fn parseExpression(self: *Parser) ZenError!NodeId {
        return self.parseAssignment();
    }

    fn parseAssignment(self: *Parser) ZenError!NodeId {
        const expr = try self.parseLogicalOr();

        if (self.match(.assign) or self.match(.plus_assign) or
            self.match(.minus_assign) or self.match(.multiply_assign) or
            self.match(.divide_assign))
        {
            const operator_token = self.previous();
            const value = try self.parseAssignment();

            const expr_node = self.ast.getNode(expr) orelse return ZenError.InvalidNodeId;
            const span = SourceSpan.init(expr_node.span.start, self.previous().span.end, self.filename);

            // Handle compound assignments as binary operations
            const binary_op: ast.BinaryExpr.BinaryOperator = switch (operator_token.type) {
                .assign => .assign,
                .plus_assign => .add_assign,
                .minus_assign => .subtract_assign,
                .multiply_assign => .multiply_assign,
                .divide_assign => .divide_assign,
                else => return ZenError.UnexpectedToken,
            };

            return self.builder.createBinaryExpr(span, expr, binary_op, value);
        }

        return expr;
    }

    fn parseLogicalOr(self: *Parser) ZenError!NodeId {
        var expr = try self.parseLogicalAnd();

        while (self.match(.or_op)) {
            // const operator = self.previous();
            const right = try self.parseLogicalAnd();

            const expr_node = self.ast.getNode(expr) orelse return ZenError.InvalidNodeId;
            const span = SourceSpan.init(expr_node.span.start, self.previous().span.end, self.filename);

            expr = try self.builder.createBinaryExpr(span, expr, .or_op, right);
        }

        return expr;
    }

    fn parseLogicalAnd(self: *Parser) ZenError!NodeId {
        var expr = try self.parseEquality();

        while (self.match(.and_op)) {
            const right = try self.parseEquality();

            const expr_node = self.ast.getNode(expr) orelse return ZenError.InvalidNodeId;
            const span = SourceSpan.init(expr_node.span.start, self.previous().span.end, self.filename);

            expr = try self.builder.createBinaryExpr(span, expr, .and_op, right);
        }

        return expr;
    }

    fn parseEquality(self: *Parser) ZenError!NodeId {
        var expr = try self.parseComparison();

        while (self.match(.equal) or self.match(.not_equal)) {
            const operator_token = self.previous();
            const right = try self.parseComparison();

            const binary_op: ast.BinaryExpr.BinaryOperator = switch (operator_token.type) {
                .equal => .equal,
                .not_equal => .not_equal,
                else => return ZenError.UnexpectedToken,
            };

            const expr_node = self.ast.getNode(expr) orelse return ZenError.InvalidNodeId;
            const span = SourceSpan.init(expr_node.span.start, self.previous().span.end, self.filename);

            expr = try self.builder.createBinaryExpr(span, expr, binary_op, right);
        }

        return expr;
    }

    fn parseComparison(self: *Parser) ZenError!NodeId {
        var expr = try self.parseTerm();

        while (self.match(.greater_than) or self.match(.greater_equal) or
            self.match(.less_than) or self.match(.less_equal) or self.match(.in_kw))
        {
            const operator_token = self.previous();
            const right = try self.parseTerm();

            const binary_op: ast.BinaryExpr.BinaryOperator = switch (operator_token.type) {
                .greater_than => .greater_than,
                .greater_equal => .greater_equal,
                .less_than => .less_than,
                .less_equal => .less_equal,
                .in_kw => .in_op,
                else => return ZenError.UnexpectedToken,
            };

            const expr_node = self.ast.getNode(expr) orelse return ZenError.InvalidNodeId;
            const span = SourceSpan.init(expr_node.span.start, self.previous().span.end, self.filename);

            expr = try self.builder.createBinaryExpr(span, expr, binary_op, right);
        }

        return expr;
    }

    fn parseTerm(self: *Parser) ZenError!NodeId {
        var expr = try self.parseFactor();

        while (self.match(.minus) or self.match(.plus)) {
            const operator_token = self.previous();
            const right = try self.parseFactor();

            const binary_op: ast.BinaryExpr.BinaryOperator = switch (operator_token.type) {
                .plus => .add,
                .minus => .subtract,
                else => return ZenError.UnexpectedToken,
            };

            const expr_node = self.ast.getNode(expr) orelse return ZenError.InvalidNodeId;
            const span = SourceSpan.init(expr_node.span.start, self.previous().span.end, self.filename);

            expr = try self.builder.createBinaryExpr(span, expr, binary_op, right);
        }

        return expr;
    }

    fn parseFactor(self: *Parser) ZenError!NodeId {
        var expr = try self.parseUnary();

        while (self.match(.divide) or self.match(.multiply) or self.match(.modulo)) {
            const operator_token = self.previous();
            const right = try self.parseUnary();

            const binary_op: ast.BinaryExpr.BinaryOperator = switch (operator_token.type) {
                .multiply => .multiply,
                .divide => .divide,
                .modulo => .modulo,
                else => return ZenError.UnexpectedToken,
            };

            const expr_node = self.ast.getNode(expr) orelse return ZenError.InvalidNodeId;
            const span = SourceSpan.init(expr_node.span.start, self.previous().span.end, self.filename);

            expr = try self.builder.createBinaryExpr(span, expr, binary_op, right);
        }

        return expr;
    }

    fn parseUnary(self: *Parser) ZenError!NodeId {
        if (self.match(.not_op) or self.match(.minus)) {
            const operator_token = self.previous();
            const right = try self.parseUnary();

            const unary_op: ast.UnaryExpr.UnaryOperator = switch (operator_token.type) {
                .not_op => .not_op,
                .minus => .minus,
                else => return ZenError.UnexpectedToken,
            };

            const span = SourceSpan.init(operator_token.span.start, self.previous().span.end, self.filename);

            const unary = ast.UnaryExpr{
                .operator = unary_op,
                .operand = right,
            };

            return self.ast.addNode(span, .{ .unary_expr = unary });
        }

        return self.parseCall();
    }

    fn parseCall(self: *Parser) ZenError!NodeId {
        var expr = try self.parsePrimary();

        while (true) {
            if (self.match(.left_paren)) {
                expr = try self.finishCall(expr);
            } else if (self.match(.dot)) {
                const name_token = try self.consume(.identifier, "Expected property name after '.'");
                const expr_node = self.ast.getNode(expr) orelse return ZenError.InvalidNodeId;
                const span = SourceSpan.init(expr_node.span.start, name_token.span.end, self.filename);

                const member = ast.MemberExpr{
                    .object = expr,
                    .property = name_token.lexeme,
                };

                expr = try self.ast.addNode(span, .{ .member_expr = member });
            } else if (self.match(.left_bracket)) {
                const index = try self.parseExpression();
                _ = try self.consume(.right_bracket, "Expected ']' after array index");

                const expr_node = self.ast.getNode(expr) orelse return ZenError.InvalidNodeId;
                const span = SourceSpan.init(expr_node.span.start, self.previous().span.end, self.filename);

                const index_expr = ast.IndexExpr{
                    .object = expr,
                    .index = index,
                };

                expr = try self.ast.addNode(span, .{ .index_expr = index_expr });
            } else {
                break;
            }
        }

        return expr;
    }

    fn finishCall(self: *Parser, callee: NodeId) ZenError!NodeId {
        var arguments = ArrayList(NodeId).init(self.allocator);
        defer arguments.deinit();

        if (!self.check(.right_paren)) {
            while (true) {
                const arg = try self.parseExpression();
                try arguments.append(arg);
                if (!self.match(.comma)) break;
            }
        }

        _ = try self.consume(.right_paren, "Expected ')' after arguments");

        const callee_node = self.ast.getNode(callee) orelse return ZenError.InvalidNodeId;
        const span = SourceSpan.init(callee_node.span.start, self.previous().span.end, self.filename);

        const call = ast.CallExpr{
            .callee = callee,
            .arguments = try arguments.toOwnedSlice(),
        };

        return self.ast.addNode(span, .{ .call_expr = call });
    }

    fn parsePrimary(self: *Parser) ZenError!NodeId {
        const token = self.advance();

        switch (token.type) {
            .true_kw => {
                const literal = ast.LiteralExpr.LiteralValue{ .boolean = true };
                return self.builder.createLiteral(token.span, literal);
            },
            .false_kw => {
                const literal = ast.LiteralExpr.LiteralValue{ .boolean = false };
                return self.builder.createLiteral(token.span, literal);
            },
            .null_kw => {
                const literal = ast.LiteralExpr.LiteralValue{ .null_value = {} };
                return self.builder.createLiteral(token.span, literal);
            },
            .integer => {
                const value = std.fmt.parseInt(i64, token.lexeme, 10) catch {
                    return ZenError.InvalidSyntax;
                };
                const literal = ast.LiteralExpr.LiteralValue{ .integer = value };
                return self.builder.createLiteral(token.span, literal);
            },
            .float => {
                const value = std.fmt.parseFloat(f64, token.lexeme) catch {
                    return ZenError.InvalidSyntax;
                };
                const literal = ast.LiteralExpr.LiteralValue{ .float = value };
                return self.builder.createLiteral(token.span, literal);
            },
            .string => {
                const literal = ast.LiteralExpr.LiteralValue{ .string = token.lexeme };
                return self.builder.createLiteral(token.span, literal);
            },
            .identifier => {
                return self.builder.createIdentifier(token.span, token.lexeme);
            },
            .left_paren => {
                const expr = try self.parseExpression();
                _ = try self.consume(.right_paren, "Expected ')' after expression");
                return expr;
            },
            .left_bracket => {
                return self.parseArrayLiteral(token.span);
            },
            else => {
                return ZenError.UnexpectedToken;
            },
        }
    }

    fn parseArrayLiteral(self: *Parser, start_span: SourceSpan) ZenError!NodeId {
        var elements = ArrayList(NodeId).init(self.allocator);
        defer elements.deinit();

        if (!self.check(.right_bracket)) {
            while (true) {
                const element = try self.parseExpression();
                try elements.append(element);
                if (!self.match(.comma)) break;
            }
        }

        _ = try self.consume(.right_bracket, "Expected ']' after array elements");

        const span = SourceSpan.init(start_span.start, self.previous().span.end, self.filename);

        const array = ast.ArrayExpr{
            .elements = try elements.toOwnedSlice(),
        };

        return self.ast.addNode(span, .{ .array_expr = array });
    }

    fn parseType(self: *Parser) ZenError!ZenType {
        // Handle optional types
        if (self.match(.question)) {
            const inner_type = try self.parseType();
            const heap_type = try self.allocator.create(ZenType);
            heap_type.* = inner_type;
            return ZenType{ .optional = heap_type };
        }

        // Handle basic types
        if (self.match(.i32_type)) return ZenType{ .primitive = .i32 };
        if (self.match(.i64_type)) return ZenType{ .primitive = .i64 };
        if (self.match(.f32_type)) return ZenType{ .primitive = .f32 };
        if (self.match(.f64_type)) return ZenType{ .primitive = .f64 };
        if (self.match(.string_type)) return ZenType{ .primitive = .string };
        if (self.match(.bool_type)) return ZenType{ .primitive = .bool };

        // Handle custom types
        if (self.check(.identifier)) {
            const name = self.advance().lexeme;

            // Handle array types
            if (self.match(.left_bracket)) {
                _ = try self.consume(.right_bracket, "Expected ']' for array type");
                const element_type = try self.allocator.create(ZenType);
                element_type.* = ZenType{ .custom = name };
                return ZenType{ .array = element_type };
            }

            return ZenType{ .custom = name };
        }

        return ZenError.UnexpectedToken;
    }

    // Utility functions
    fn match(self: *Parser, token_type: TokenType) bool {
        if (self.check(token_type)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn check(self: *Parser, token_type: TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().type == token_type;
    }

    fn advance(self: *Parser) Token {
        if (!self.isAtEnd()) self.current += 1;
        return self.previous();
    }

    fn isAtEnd(self: *Parser) bool {
        return self.peek().type == .eof;
    }

    fn peek(self: *Parser) Token {
        return self.tokens[self.current];
    }

    fn previous(self: *Parser) Token {
        return self.tokens[self.current - 1];
    }

    fn consume(self: *Parser, token_type: TokenType, message: []const u8) ZenError!Token {
        if (self.check(token_type)) return self.advance();

        _ = message; // TODO: Use for better error reporting
        return ZenError.UnexpectedToken;
    }

    fn consumeStatementEnd(self: *Parser) ZenError!void {
        if (self.match(.semicolon) or self.match(.newline) or self.isAtEnd()) {
            return;
        }
        return ZenError.UnexpectedToken;
    }
};

test "parser basic function" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const source = "func add(a: i32, b: i32) -> i32 { return a + b; }";

    var lex = lexer.Lexer.init(allocator, source, "test.zen");
    defer lex.deinit();

    const tokens = try lex.tokenize();
    defer allocator.free(tokens);

    var parser = Parser.init(allocator, tokens, "test.zen");
    defer parser.deinit();

    const ast_result = try parser.parse();

    try testing.expect(ast_result.nodes.items.len > 0);
}
