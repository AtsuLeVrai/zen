const std = @import("std");
const lexer = @import("lexer.zig");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Position = lexer.Position;
const ArrayList = std.ArrayList;

pub const TypeKind = enum {
    i32,
    f64,
    string,
    bool,
    void,
    optional,
    array,
    custom,
};

pub const Type = struct {
    kind: TypeKind,
    name: ?[]const u8 = null,
    element_type: ?*Type = null,
    position: Position,
    
    pub fn init(kind: TypeKind, position: Position) Type {
        return Type{
            .kind = kind,
            .position = position,
        };
    }
    
    pub fn initWithName(kind: TypeKind, name: []const u8, position: Position) Type {
        return Type{
            .kind = kind,
            .name = name,
            .position = position,
        };
    }
    
    pub fn initOptional(element_type: *Type, position: Position) Type {
        return Type{
            .kind = .optional,
            .element_type = element_type,
            .position = position,
        };
    }
    
    pub fn initArray(element_type: *Type, position: Position) Type {
        return Type{
            .kind = .array,
            .element_type = element_type,
            .position = position,
        };
    }
};

pub const BinaryOp = enum {
    add,
    subtract,
    multiply,
    divide,
    modulo,
    equal,
    not_equal,
    less_than,
    less_equal,
    greater_than,
    greater_equal,
    logical_and,
    logical_or,
};

pub const UnaryOp = enum {
    minus,
    logical_not,
};

pub const AssignmentOp = enum {
    assign,
    add_assign,
    subtract_assign,
    multiply_assign,
    divide_assign,
};

pub const ExpressionKind = enum {
    literal,
    identifier,
    binary,
    unary,
    assignment,
    call,
    member_access,
    array_access,
    string_interpolation,
    array_literal,
};

pub const LiteralValue = union(enum) {
    integer: i64,
    float: f64,
    string: []const u8,
    boolean: bool,
    null_value,
};

pub const StringInterpolation = struct {
    parts: []const StringInterpolationPart,
    position: Position,
};

pub const StringInterpolationPart = union(enum) {
    text: []const u8,
    expression: *Expression,
};

pub const Expression = struct {
    kind: ExpressionKind,
    type_annotation: ?*Type = null,
    position: Position,
    data: union(ExpressionKind) {
        literal: LiteralValue,
        identifier: []const u8,
        binary: struct {
            left: *Expression,
            operator: BinaryOp,
            right: *Expression,
        },
        unary: struct {
            operator: UnaryOp,
            operand: *Expression,
        },
        assignment: struct {
            target: *Expression,
            operator: AssignmentOp,
            value: *Expression,
        },
        call: struct {
            callee: *Expression,
            arguments: []const *Expression,
        },
        member_access: struct {
            object: *Expression,
            member: []const u8,
        },
        array_access: struct {
            array: *Expression,
            index: *Expression,
        },
        string_interpolation: StringInterpolation,
        array_literal: []const *Expression,
    },
};

pub const StatementKind = enum {
    expression,
    variable_declaration,
    return_statement,
    if_statement,
    while_statement,
    for_statement,
    switch_statement,
    block,
};

pub const VariableDeclaration = struct {
    is_const: bool,
    name: []const u8,
    type_annotation: ?*Type,
    initializer: ?*Expression,
    position: Position,
};

pub const IfStatement = struct {
    condition: *Expression,
    then_stmt: *Statement,
    else_stmt: ?*Statement,
    position: Position,
};

pub const WhileStatement = struct {
    condition: *Expression,
    body: *Statement,
    position: Position,
};

pub const ForStatement = struct {
    init: ?*Statement,
    condition: ?*Expression,
    increment: ?*Expression,
    body: *Statement,
    position: Position,
};

pub const SwitchCase = struct {
    value: ?*Expression,
    statements: []const *Statement,
    position: Position,
};

pub const SwitchStatement = struct {
    expression: *Expression,
    cases: []const SwitchCase,
    position: Position,
};

pub const BlockStatement = struct {
    statements: []const *Statement,
    position: Position,
};

pub const Statement = struct {
    kind: StatementKind,
    position: Position,
    data: union(StatementKind) {
        expression: *Expression,
        variable_declaration: VariableDeclaration,
        return_statement: ?*Expression,
        if_statement: IfStatement,
        while_statement: WhileStatement,
        for_statement: ForStatement,
        switch_statement: SwitchStatement,
        block: BlockStatement,
    },
};

pub const Parameter = struct {
    name: []const u8,
    param_type: *Type,
    position: Position,
};

pub const FunctionDeclaration = struct {
    name: []const u8,
    parameters: []const Parameter,
    return_type: ?*Type,
    body: *Statement,
    position: Position,
};

pub const Program = struct {
    functions: []const FunctionDeclaration,
    position: Position,
};

pub const AstAllocator = struct {
    arena: ArenaAllocator,
    
    pub fn init(alloc: Allocator) AstAllocator {
        return AstAllocator{
            .arena = ArenaAllocator.init(alloc),
        };
    }
    
    pub fn deinit(self: *AstAllocator) void {
        self.arena.deinit();
    }
    
    pub fn allocator(self: *AstAllocator) Allocator {
        return self.arena.allocator();
    }
    
    pub fn createExpression(self: *AstAllocator, kind: ExpressionKind, position: Position) !*Expression {
        const expr = try self.allocator().create(Expression);
        expr.* = Expression{
            .kind = kind,
            .position = position,
            .data = undefined,
        };
        return expr;
    }
    
    pub fn createStatement(self: *AstAllocator, kind: StatementKind, position: Position) !*Statement {
        const stmt = try self.allocator().create(Statement);
        stmt.* = Statement{
            .kind = kind,
            .position = position,
            .data = undefined,
        };
        return stmt;
    }
    
    pub fn createType(self: *AstAllocator, kind: TypeKind, position: Position) !*Type {
        const type_node = try self.allocator().create(Type);
        type_node.* = Type.init(kind, position);
        return type_node;
    }
    
    pub fn createLiteralExpression(self: *AstAllocator, value: LiteralValue, position: Position) !*Expression {
        const expr = try self.createExpression(.literal, position);
        expr.data = .{ .literal = value };
        return expr;
    }
    
    pub fn createIdentifierExpression(self: *AstAllocator, name: []const u8, position: Position) !*Expression {
        const expr = try self.createExpression(.identifier, position);
        expr.data = .{ .identifier = name };
        return expr;
    }
    
    pub fn createBinaryExpression(self: *AstAllocator, left: *Expression, operator: BinaryOp, right: *Expression, position: Position) !*Expression {
        const expr = try self.createExpression(.binary, position);
        expr.data = .{ .binary = .{ .left = left, .operator = operator, .right = right } };
        return expr;
    }
    
    pub fn createUnaryExpression(self: *AstAllocator, operator: UnaryOp, operand: *Expression, position: Position) !*Expression {
        const expr = try self.createExpression(.unary, position);
        expr.data = .{ .unary = .{ .operator = operator, .operand = operand } };
        return expr;
    }
    
    pub fn createAssignmentExpression(self: *AstAllocator, target: *Expression, operator: AssignmentOp, value: *Expression, position: Position) !*Expression {
        const expr = try self.createExpression(.assignment, position);
        expr.data = .{ .assignment = .{ .target = target, .operator = operator, .value = value } };
        return expr;
    }
    
    pub fn createCallExpression(self: *AstAllocator, callee: *Expression, arguments: []const *Expression, position: Position) !*Expression {
        const expr = try self.createExpression(.call, position);
        expr.data = .{ .call = .{ .callee = callee, .arguments = arguments } };
        return expr;
    }
    
    pub fn createMemberAccessExpression(self: *AstAllocator, object: *Expression, member: []const u8, position: Position) !*Expression {
        const expr = try self.createExpression(.member_access, position);
        expr.data = .{ .member_access = .{ .object = object, .member = member } };
        return expr;
    }
    
    pub fn createArrayAccessExpression(self: *AstAllocator, array: *Expression, index: *Expression, position: Position) !*Expression {
        const expr = try self.createExpression(.array_access, position);
        expr.data = .{ .array_access = .{ .array = array, .index = index } };
        return expr;
    }
    
    pub fn createArrayLiteralExpression(self: *AstAllocator, elements: []const *Expression, position: Position) !*Expression {
        const expr = try self.createExpression(.array_literal, position);
        expr.data = .{ .array_literal = elements };
        return expr;
    }
    
    pub fn createExpressionStatement(self: *AstAllocator, expression: *Expression) !*Statement {
        const stmt = try self.createStatement(.expression, expression.position);
        stmt.data = .{ .expression = expression };
        return stmt;
    }
    
    pub fn createVariableDeclaration(self: *AstAllocator, is_const: bool, name: []const u8, type_annotation: ?*Type, initializer: ?*Expression, position: Position) !*Statement {
        const stmt = try self.createStatement(.variable_declaration, position);
        stmt.data = .{ .variable_declaration = VariableDeclaration{
            .is_const = is_const,
            .name = name,
            .type_annotation = type_annotation,
            .initializer = initializer,
            .position = position,
        } };
        return stmt;
    }
    
    pub fn createReturnStatement(self: *AstAllocator, expression: ?*Expression, position: Position) !*Statement {
        const stmt = try self.createStatement(.return_statement, position);
        stmt.data = .{ .return_statement = expression };
        return stmt;
    }
    
    pub fn createIfStatement(self: *AstAllocator, condition: *Expression, then_stmt: *Statement, else_stmt: ?*Statement, position: Position) !*Statement {
        const stmt = try self.createStatement(.if_statement, position);
        stmt.data = .{ .if_statement = IfStatement{
            .condition = condition,
            .then_stmt = then_stmt,
            .else_stmt = else_stmt,
            .position = position,
        } };
        return stmt;
    }
    
    pub fn createWhileStatement(self: *AstAllocator, condition: *Expression, body: *Statement, position: Position) !*Statement {
        const stmt = try self.createStatement(.while_statement, position);
        stmt.data = .{ .while_statement = WhileStatement{
            .condition = condition,
            .body = body,
            .position = position,
        } };
        return stmt;
    }
    
    pub fn createBlockStatement(self: *AstAllocator, statements: []const *Statement, position: Position) !*Statement {
        const stmt = try self.createStatement(.block, position);
        stmt.data = .{ .block = BlockStatement{
            .statements = statements,
            .position = position,
        } };
        return stmt;
    }
};