const std = @import("std");
const types = @import("types.zig");

pub const Position = struct {
    line: u32,
    column: u32,
};

pub const NodeType = enum {
    program,
    function_declaration,
    variable_declaration,
    block_statement,
    return_statement,
    expression_statement,
    if_statement,
    while_statement,
    assignment_expression,
    binary_expression,
    unary_expression,
    call_expression,
    identifier,
    number_literal,
    string_literal,
    boolean_literal,
};

pub const Node = struct {
    node_type: NodeType,
    position: Position,
    data: NodeData,

    const NodeData = union(NodeType) {
        program: Program,
        function_declaration: FunctionDeclaration,
        variable_declaration: VariableDeclaration,
        block_statement: BlockStatement,
        return_statement: ReturnStatement,
        expression_statement: ExpressionStatement,
        if_statement: IfStatement,
        while_statement: WhileStatement,
        assignment_expression: AssignmentExpression,
        binary_expression: BinaryExpression,
        unary_expression: UnaryExpression,
        call_expression: CallExpression,
        identifier: Identifier,
        number_literal: NumberLiteral,
        string_literal: StringLiteral,
        boolean_literal: BooleanLiteral,
    };
};

pub const Program = struct {
    statements: []*Node,
};

pub const FunctionDeclaration = struct {
    name: []const u8,
    parameters: []Parameter,
    return_type: types.Type,
    body: *Node, // BlockStatement
};

pub const Parameter = struct {
    name: []const u8,
    param_type: types.Type,
};

pub const VariableDeclaration = struct {
    name: []const u8,
    var_type: ?types.Type, // null for type inference
    is_mutable: bool, // let vs const
    initializer: ?*Node,
};

pub const BlockStatement = struct {
    statements: []*Node,
};

pub const ReturnStatement = struct {
    value: ?*Node,
};

pub const ExpressionStatement = struct {
    expression: *Node,
};

pub const IfStatement = struct {
    condition: *Node,
    then_branch: *Node,
    else_branch: ?*Node,
};

pub const WhileStatement = struct {
    condition: *Node,
    body: *Node,
};

pub const AssignmentExpression = struct {
    target: *Node, // Identifier
    value: *Node,
};

pub const BinaryOperator = enum {
    add,
    subtract,
    multiply,
    divide,
    equal,
    not_equal,
    less_than,
    less_equal,
    greater_than,
    greater_equal,
    logical_and,
    logical_or,
};

pub const BinaryExpression = struct {
    left: *Node,
    operator: BinaryOperator,
    right: *Node,
};

pub const UnaryOperator = enum {
    minus,
    logical_not,
};

pub const UnaryExpression = struct {
    operator: UnaryOperator,
    operand: *Node,
};

pub const CallExpression = struct {
    function: *Node, // Identifier
    arguments: []*Node,
};

pub const Identifier = struct {
    name: []const u8,
};

pub const NumberLiteral = struct {
    value: f64,
    is_integer: bool,
};

pub const StringLiteral = struct {
    value: []const u8,
};

pub const BooleanLiteral = struct {
    value: bool,
};

// Helper functions for creating nodes
pub fn createNode(allocator: std.mem.Allocator, node_type: NodeType, position: Position) !*Node {
    const node = try allocator.create(Node);
    node.node_type = node_type;
    node.position = position;
    return node;
}

pub fn createProgram(allocator: std.mem.Allocator, statements: []*Node) !*Node {
    const node = try createNode(allocator, .program, Position{ .line = 1, .column = 1 });
    node.data = .{ .program = Program{ .statements = statements } };
    return node;
}

pub fn createFunctionDeclaration(
    allocator: std.mem.Allocator,
    position: Position,
    name: []const u8,
    parameters: []Parameter,
    return_type: types.Type,
    body: *Node,
) !*Node {
    const node = try createNode(allocator, .function_declaration, position);
    node.data = .{ .function_declaration = FunctionDeclaration{
        .name = name,
        .parameters = parameters,
        .return_type = return_type,
        .body = body,
    } };
    return node;
}

pub fn createIdentifier(allocator: std.mem.Allocator, position: Position, name: []const u8) !*Node {
    const node = try createNode(allocator, .identifier, position);
    node.data = .{ .identifier = Identifier{ .name = name } };
    return node;
}

pub fn createNumberLiteral(allocator: std.mem.Allocator, position: Position, value: f64, is_integer: bool) !*Node {
    const node = try createNode(allocator, .number_literal, position);
    node.data = .{ .number_literal = NumberLiteral{ .value = value, .is_integer = is_integer } };
    return node;
}

// Print AST for debugging
pub fn printNode(node: *Node, indent: usize) void {
    for (0..indent) |_| std.debug.print("  ");

    switch (node.node_type) {
        .program => {
            std.debug.print("Program\n");
            for (node.data.program.statements) |stmt| {
                printNode(stmt, indent + 1);
            }
        },
        .function_declaration => {
            const func = node.data.function_declaration;
            std.debug.print("FunctionDeclaration: {s}\n", .{func.name});
            printNode(func.body, indent + 1);
        },
        .identifier => {
            std.debug.print("Identifier: {s}\n", .{node.data.identifier.name});
        },
        .number_literal => {
            const num = node.data.number_literal;
            std.debug.print("Number: {d}\n", .{num.value});
        },
        else => {
            std.debug.print("{}\n", .{node.node_type});
        },
    }
}

// Cleanup function for AST nodes
pub fn destroyNode(allocator: std.mem.Allocator, node: *Node) void {
    switch (node.data) {
        .program => |program| {
            for (program.statements) |stmt| {
                destroyNode(allocator, stmt);
            }
            allocator.free(program.statements);
        },
        .function_declaration => |func| {
            allocator.free(func.parameters);
            destroyNode(allocator, func.body);
        },
        .block_statement => |block| {
            for (block.statements) |stmt| {
                destroyNode(allocator, stmt);
            }
            allocator.free(block.statements);
        },
        .return_statement => |ret| {
            if (ret.value) |value| {
                destroyNode(allocator, value);
            }
        },
        .binary_expression => |binary| {
            destroyNode(allocator, binary.left);
            destroyNode(allocator, binary.right);
        },
        .unary_expression => |unary| {
            destroyNode(allocator, unary.operand);
        },
        .call_expression => |call| {
            destroyNode(allocator, call.function);
            for (call.arguments) |arg| {
                destroyNode(allocator, arg);
            }
            allocator.free(call.arguments);
        },
        .variable_declaration => |var_decl| {
            if (var_decl.initializer) |init| {
                destroyNode(allocator, init);
            }
        },
        .expression_statement => |expr_stmt| {
            destroyNode(allocator, expr_stmt.expression);
        },
        .if_statement => |if_stmt| {
            destroyNode(allocator, if_stmt.condition);
            destroyNode(allocator, if_stmt.then_branch);
            if (if_stmt.else_branch) |else_stmt| {
                destroyNode(allocator, else_stmt);
            }
        },
        .while_statement => |while_stmt| {
            destroyNode(allocator, while_stmt.condition);
            destroyNode(allocator, while_stmt.body);
        },
        .assignment_expression => |assign| {
            destroyNode(allocator, assign.target);
            destroyNode(allocator, assign.value);
        },
        // Leaf nodes don't need special cleanup
        .number_literal, .string_literal, .boolean_literal, .identifier => {},
    }
    allocator.destroy(node);
}