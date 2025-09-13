const std = @import("std");
const ast = @import("ast.zig");
const types = @import("types.zig");

pub const TypeChecker = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    environment: types.TypeEnvironment,
    current_function_return_type: ?types.Type,

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .environment = types.TypeEnvironment.init(allocator),
            .current_function_return_type = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.environment.deinit();
    }

    pub fn checkProgram(self: *Self, program: *ast.Node) !void {
        if (program.node_type != .program) {
            return types.TypeError.TypeMismatch;
        }

        // First pass: collect function declarations
        for (program.data.program.statements) |stmt| {
            if (stmt.node_type == .function_declaration) {
                try self.collectFunctionDeclaration(stmt);
            }
        }

        // Add built-in functions
        var builtins = try types.getBuiltinFunctions(self.allocator);
        defer types.deinitBuiltinFunctions(self.allocator, &builtins);

        var iterator = builtins.iterator();
        while (iterator.next()) |entry| {
            try self.environment.defineFunction(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Second pass: type check all statements
        for (program.data.program.statements) |stmt| {
            _ = try self.checkStatement(stmt);
        }
    }

    fn collectFunctionDeclaration(self: *Self, node: *ast.Node) !void {
        const func_decl = node.data.function_declaration;

        // Convert parameters to types
        var param_types = std.ArrayList(types.Type){};
        defer param_types.deinit(self.allocator);

        for (func_decl.parameters) |param| {
            try param_types.append(self.allocator, param.param_type);
        }

        const func_type = types.FunctionType{
            .parameters = try param_types.toOwnedSlice(self.allocator),
            .return_type = func_decl.return_type,
        };

        try self.environment.defineFunction(func_decl.name, func_type);
    }

    fn checkStatement(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        switch (node.node_type) {
            .function_declaration => return self.checkFunctionDeclaration(node),
            .variable_declaration => return self.checkVariableDeclaration(node),
            .block_statement => return self.checkBlockStatement(node),
            .return_statement => return self.checkReturnStatement(node),
            .expression_statement => return self.checkExpressionStatement(node),
            .if_statement => return self.checkIfStatement(node),
            .while_statement => return self.checkWhileStatement(node),
            else => return types.TypeError.TypeMismatch,
        }
    }

    fn checkFunctionDeclaration(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const func_decl = node.data.function_declaration;

        // Set current function context
        const previous_return_type = self.current_function_return_type;
        self.current_function_return_type = func_decl.return_type;
        defer self.current_function_return_type = previous_return_type;

        // Create new scope for function parameters
        // Note: In a full implementation, we'd push a new scope here
        for (func_decl.parameters) |param| {
            try self.environment.defineVariable(param.name, param.param_type);
        }

        // Type check function body
        const body_type = try self.checkStatement(func_decl.body);
        _ = body_type; // Function body type is checked via return statements

        return .void;
    }

    fn checkVariableDeclaration(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const var_decl = node.data.variable_declaration;

        var var_type = var_decl.var_type orelse .unknown;

        // Type check initializer if present
        if (var_decl.initializer) |initializer| {
            const init_type = try self.checkExpression(initializer);

            if (var_type == .unknown) {
                // Type inference
                var_type = init_type;
            } else {
                // Type compatibility check
                if (!types.Type.canAssignTo(init_type, var_type)) {
                    std.debug.print("Type error: Cannot assign {s} to {s}\n", .{ init_type.toString(), var_type.toString() });
                    return types.TypeError.TypeMismatch;
                }
            }
        }

        try self.environment.defineVariable(var_decl.name, var_type);
        return .void;
    }

    fn checkBlockStatement(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const block = node.data.block_statement;

        for (block.statements) |stmt| {
            _ = try self.checkStatement(stmt);
        }

        return .void;
    }

    fn checkReturnStatement(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const ret_stmt = node.data.return_statement;

        const return_type = if (ret_stmt.value) |value|
            try self.checkExpression(value)
        else
            .void;

        if (self.current_function_return_type) |expected| {
            if (!types.Type.canAssignTo(return_type, expected)) {
                std.debug.print("Return type mismatch: expected {s}, got {s}\n", .{ expected.toString(), return_type.toString() });
                return types.TypeError.ReturnTypeMismatch;
            }
        }

        return .void;
    }

    fn checkExpressionStatement(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const expr_stmt = node.data.expression_statement;
        _ = try self.checkExpression(expr_stmt.expression);
        return .void;
    }

    fn checkIfStatement(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const if_stmt = node.data.if_statement;

        const condition_type = try self.checkExpression(if_stmt.condition);
        if (condition_type != .bool) {
            std.debug.print("If condition must be bool, got {s}\n", .{condition_type.toString()});
            return types.TypeError.TypeMismatch;
        }

        _ = try self.checkStatement(if_stmt.then_branch);

        if (if_stmt.else_branch) |else_branch| {
            _ = try self.checkStatement(else_branch);
        }

        return .void;
    }

    fn checkWhileStatement(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const while_stmt = node.data.while_statement;

        const condition_type = try self.checkExpression(while_stmt.condition);
        if (condition_type != .bool) {
            std.debug.print("While condition must be bool, got {s}\n", .{condition_type.toString()});
            return types.TypeError.TypeMismatch;
        }

        _ = try self.checkStatement(while_stmt.body);
        return .void;
    }

    fn checkExpression(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        switch (node.node_type) {
            .assignment_expression => return self.checkAssignmentExpression(node),
            .binary_expression => return self.checkBinaryExpression(node),
            .unary_expression => return self.checkUnaryExpression(node),
            .call_expression => return self.checkCallExpression(node),
            .identifier => return self.checkIdentifier(node),
            .number_literal => return self.checkNumberLiteral(node),
            .string_literal => return .string,
            .boolean_literal => return .bool,
            else => return types.TypeError.TypeMismatch,
        }
    }

    fn checkAssignmentExpression(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const assign_expr = node.data.assignment_expression;

        // Check that target is an identifier
        if (assign_expr.target.node_type != .identifier) {
            return types.TypeError.InvalidAssignment;
        }

        const target_name = assign_expr.target.data.identifier.name;
        const target_type = self.environment.lookupVariable(target_name) orelse {
            std.debug.print("Undefined variable: {s}\n", .{target_name});
            return types.TypeError.UndefinedVariable;
        };

        const value_type = try self.checkExpression(assign_expr.value);

        if (!types.Type.canAssignTo(value_type, target_type)) {
            std.debug.print("Assignment type mismatch: cannot assign {s} to {s}\n", .{ value_type.toString(), target_type.toString() });
            return types.TypeError.TypeMismatch;
        }

        return target_type;
    }

    fn checkBinaryExpression(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const bin_expr = node.data.binary_expression;

        const left_type = try self.checkExpression(bin_expr.left);
        const right_type = try self.checkExpression(bin_expr.right);

        return switch (bin_expr.operator) {
            .add, .subtract, .multiply, .divide => {
                if (!left_type.isNumeric() or !right_type.isNumeric()) {
                    std.debug.print("Arithmetic operation requires numeric types, got {s} and {s}\n", .{ left_type.toString(), right_type.toString() });
                    return types.TypeError.InvalidOperation;
                }
                return types.Type.getCommonType(left_type, right_type);
            },
            .equal, .not_equal => {
                // Allow comparison between any compatible types
                return .bool;
            },
            .less_than, .less_equal, .greater_than, .greater_equal => {
                if (!left_type.isNumeric() or !right_type.isNumeric()) {
                    std.debug.print("Comparison operation requires numeric types, got {s} and {s}\n", .{ left_type.toString(), right_type.toString() });
                    return types.TypeError.InvalidOperation;
                }
                return .bool;
            },
            .logical_and, .logical_or => {
                if (left_type != .bool or right_type != .bool) {
                    std.debug.print("Logical operation requires bool types, got {s} and {s}\n", .{ left_type.toString(), right_type.toString() });
                    return types.TypeError.InvalidOperation;
                }
                return .bool;
            },
        };
    }

    fn checkUnaryExpression(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const unary_expr = node.data.unary_expression;

        const operand_type = try self.checkExpression(unary_expr.operand);

        return switch (unary_expr.operator) {
            .minus => {
                if (!operand_type.isNumeric()) {
                    std.debug.print("Unary minus requires numeric type, got {s}\n", .{operand_type.toString()});
                    return types.TypeError.InvalidOperation;
                }
                return operand_type;
            },
            .logical_not => {
                if (operand_type != .bool) {
                    std.debug.print("Logical not requires bool type, got {s}\n", .{operand_type.toString()});
                    return types.TypeError.InvalidOperation;
                }
                return .bool;
            },
        };
    }

    fn checkCallExpression(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const call_expr = node.data.call_expression;

        // Function must be an identifier
        if (call_expr.function.node_type != .identifier) {
            return types.TypeError.TypeMismatch;
        }

        const func_name = call_expr.function.data.identifier.name;
        const func_type = self.environment.lookupFunction(func_name) orelse {
            std.debug.print("Undefined function: {s}\n", .{func_name});
            return types.TypeError.UndefinedFunction;
        };

        // Check argument count
        if (call_expr.arguments.len != func_type.parameters.len) {
            std.debug.print("Function {s} expects {} arguments, got {}\n", .{ func_name, func_type.parameters.len, call_expr.arguments.len });
            return types.TypeError.ArgumentCountMismatch;
        }

        // Check argument types
        for (call_expr.arguments, 0..) |arg, i| {
            const arg_type = try self.checkExpression(arg);
            const param_type = func_type.parameters[i];

            if (!types.Type.canAssignTo(arg_type, param_type)) {
                std.debug.print("Argument {} type mismatch: expected {s}, got {s}\n", .{ i, param_type.toString(), arg_type.toString() });
                return types.TypeError.TypeMismatch;
            }
        }

        return func_type.return_type;
    }

    fn checkIdentifier(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        const identifier = node.data.identifier;

        return self.environment.lookupVariable(identifier.name) orelse {
            std.debug.print("Undefined variable: {s}\n", .{identifier.name});
            return types.TypeError.UndefinedVariable;
        };
    }

    fn checkNumberLiteral(self: *Self, node: *ast.Node) types.TypeError!types.Type {
        _ = self; // Mark as used
        const num_literal = node.data.number_literal;
        return if (num_literal.is_integer) .i32 else .f64;
    }
};
