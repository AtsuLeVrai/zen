const std = @import("std");
const llvm = @import("llvm");
const ast = @import("ast.zig");
const types = @import("types.zig");

// LLVM-C API Code Generator using llvm-zig bindings
// This replaces the LLVM IR text generation with direct LLVM API calls

pub const CodeGenError = error{
    UndefinedVariable,
    UndefinedFunction,
    InvalidOperation,
    OutOfMemory,
    LLVMError,
};

pub const CodeGenerator = struct {
    const Self = @This();

    allocator: std.mem.Allocator,

    // LLVM Context and Module
    context: llvm.LLVMContextRef,
    module: llvm.LLVMModuleRef,
    builder: llvm.LLVMBuilderRef,

    // Function and variable tracking
    current_function: ?llvm.LLVMValueRef,
    local_variables: std.StringHashMap(llvm.LLVMValueRef),
    functions: std.StringHashMap(llvm.LLVMValueRef),

    pub fn init(allocator: std.mem.Allocator) Self {
        const context = llvm.LLVMContextCreate();
        const module = llvm.LLVMModuleCreateWithNameInContext("zen_module", context);
        const builder = llvm.LLVMCreateBuilderInContext(context);

        return Self{
            .allocator = allocator,
            .context = context,
            .module = module,
            .builder = builder,
            .current_function = null,
            .local_variables = std.StringHashMap(llvm.LLVMValueRef).init(allocator),
            .functions = std.StringHashMap(llvm.LLVMValueRef).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.local_variables.deinit();
        self.functions.deinit();
        llvm.LLVMDisposeBuilder(self.builder);
        llvm.LLVMDisposeModule(self.module);
        llvm.LLVMContextDispose(self.context);
    }

    pub fn generateProgram(self: *Self, program: *ast.Node, filename: []const u8) !void {
        if (program.node_type != .program) {
            return CodeGenError.InvalidOperation;
        }

        // Set target triple
        const target_triple = llvm.LLVMGetDefaultTargetTriple();
        llvm.LLVMSetTarget(self.module, target_triple);

        // Create built-in functions
        try self.createBuiltinFunctions();

        // Generate code for all statements
        for (program.data.program.statements) |stmt| {
            try self.generateStatement(stmt);
        }

        // Verify the module
        var error_msg: [*c]u8 = null;
        if (llvm.LLVMVerifyModule(self.module, llvm.LLVMVerifierFailureAction.LLVMPrintMessageAction, &error_msg) != 0) {
            std.debug.print("LLVM Module verification failed: {s}\n", .{error_msg});
            llvm.LLVMDisposeMessage(error_msg);
            return CodeGenError.LLVMError;
        }

        // Output LLVM IR to file
        const output_filename = try std.fmt.allocPrint(self.allocator, "{s}.ll", .{filename[0 .. filename.len - 4]});
        defer self.allocator.free(output_filename);

        const output_filename_cstr = try std.fmt.allocPrintZ(self.allocator, "{s}", .{output_filename});
        defer self.allocator.free(output_filename_cstr);

        var error_message: [*c]u8 = null;
        if (llvm.LLVMPrintModuleToFile(self.module, output_filename_cstr.ptr, &error_message) != 0) {
            std.debug.print("Failed to write LLVM IR file: {s}\n", .{error_message});
            llvm.LLVMDisposeMessage(error_message);
            return CodeGenError.LLVMError;
        }

        std.debug.print("Generated LLVM IR: {s}\n", .{output_filename});
    }

    fn createBuiltinFunctions(self: *Self) !void {
        // Create printf declaration
        const printf_type = llvm.LLVMFunctionType(
            llvm.LLVMInt32TypeInContext(self.context), // return type: i32
            @ptrCast(&llvm.LLVMPointerTypeInContext(self.context, 0)), // first param: i8*
            1, // param count
            1  // is_varargs
        );
        const printf_func = llvm.LLVMAddFunction(self.module, "printf", printf_type);
        try self.functions.put("printf", printf_func);

        // Create print function (wrapper around printf)
        const print_type = llvm.LLVMFunctionType(
            llvm.LLVMVoidTypeInContext(self.context), // return type: void
            @ptrCast(&llvm.LLVMPointerTypeInContext(self.context, 0)), // param: i8*
            1, // param count
            0  // is_varargs
        );
        const print_func = llvm.LLVMAddFunction(self.module, "print", print_type);
        try self.functions.put("print", print_func);

        // Implement print function body
        const print_entry = llvm.LLVMAppendBasicBlockInContext(self.context, print_func, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.builder, print_entry);

        // Get the parameter
        const str_param = llvm.LLVMGetParam(print_func, 0);

        // Create format string for printf ("%s\n")
        const format_str = llvm.LLVMBuildGlobalStringPtr(self.builder, "%s\n", "print.fmt");

        // Call printf
        const printf_args = [_]llvm.LLVMValueRef{ format_str, str_param };
        _ = llvm.LLVMBuildCall2(self.builder, printf_type, printf_func, @ptrCast(&printf_args), 2, "");

        // Return void
        _ = llvm.LLVMBuildRetVoid(self.builder);

        // Create print_int function
        const print_int_type = llvm.LLVMFunctionType(
            llvm.LLVMVoidTypeInContext(self.context), // return type: void
            @ptrCast(&llvm.LLVMInt32TypeInContext(self.context)), // param: i32
            1, // param count
            0  // is_varargs
        );
        const print_int_func = llvm.LLVMAddFunction(self.module, "print_int", print_int_type);
        try self.functions.put("print_int", print_int_func);

        // Implement print_int function body
        const print_int_entry = llvm.LLVMAppendBasicBlockInContext(self.context, print_int_func, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.builder, print_int_entry);

        // Get the parameter
        const int_param = llvm.LLVMGetParam(print_int_func, 0);

        // Create format string for printf ("%d\n")
        const int_format_str = llvm.LLVMBuildGlobalStringPtr(self.builder, "%d\n", "print_int.fmt");

        // Call printf
        const printf_int_args = [_]llvm.LLVMValueRef{ int_format_str, int_param };
        _ = llvm.LLVMBuildCall2(self.builder, printf_type, printf_func, @ptrCast(&printf_int_args), 2, "");

        // Return void
        _ = llvm.LLVMBuildRetVoid(self.builder);
    }

    fn generateStatement(self: *Self, node: *ast.Node) CodeGenError!void {
        switch (node.node_type) {
            .function_declaration => try self.generateFunctionDeclaration(node),
            .variable_declaration => try self.generateVariableDeclaration(node),
            .block_statement => try self.generateBlockStatement(node),
            .return_statement => try self.generateReturnStatement(node),
            .expression_statement => try self.generateExpressionStatement(node),
            .if_statement => try self.generateIfStatement(node),
            .while_statement => try self.generateWhileStatement(node),
            else => return CodeGenError.InvalidOperation,
        }
    }

    fn generateFunctionDeclaration(self: *Self, node: *ast.Node) CodeGenError!void {
        const func_decl = node.data.function_declaration;

        // Clear local variables for new function
        self.local_variables.clearAndFree();

        // Create function type
        const return_llvm_type = self.typeToLLVMType(func_decl.return_type);

        var param_types = std.ArrayList(llvm.LLVMTypeRef).init(self.allocator);
        defer param_types.deinit();

        for (func_decl.parameters) |param| {
            try param_types.append(self.typeToLLVMType(param.param_type));
        }

        const function_type = llvm.LLVMFunctionType(
            return_llvm_type,
            if (param_types.items.len > 0) param_types.items.ptr else null,
            @intCast(param_types.items.len),
            0 // not varargs
        );

        // Create function
        const func_name_cstr = try std.fmt.allocPrintZ(self.allocator, "{s}", .{func_decl.name});
        defer self.allocator.free(func_name_cstr);

        const function = llvm.LLVMAddFunction(self.module, func_name_cstr.ptr, function_type);
        try self.functions.put(func_decl.name, function);
        self.current_function = function;

        // Create entry block
        const entry_block = llvm.LLVMAppendBasicBlockInContext(self.context, function, "entry");
        llvm.LLVMPositionBuilderAtEnd(self.builder, entry_block);

        // Set parameter names and create allocas for parameters
        for (func_decl.parameters, 0..) |param, i| {
            const param_value = llvm.LLVMGetParam(function, @intCast(i));

            // Set parameter name
            const param_name_cstr = try std.fmt.allocPrintZ(self.allocator, "{s}", .{param.name});
            defer self.allocator.free(param_name_cstr);
            llvm.LLVMSetValueName2(param_value, param_name_cstr.ptr, param_name_cstr.len);

            // Create alloca for parameter and store the parameter value
            const param_alloca = llvm.LLVMBuildAlloca(self.builder, self.typeToLLVMType(param.param_type), param_name_cstr.ptr);
            _ = llvm.LLVMBuildStore(self.builder, param_value, param_alloca);

            try self.local_variables.put(param.name, param_alloca);
        }

        // Generate function body
        if (func_decl.body.node_type == .block_statement) {
            const block = func_decl.body.data.block_statement;
            for (block.statements) |stmt| {
                try self.generateStatement(stmt);
            }
        }

        // Add return void if function doesn't end with return and return type is void
        if (func_decl.return_type == .void) {
            const last_block = llvm.LLVMGetInsertBlock(self.builder);
            if (llvm.LLVMGetBasicBlockTerminator(last_block) == null) {
                _ = llvm.LLVMBuildRetVoid(self.builder);
            }
        }
    }

    fn generateVariableDeclaration(self: *Self, node: *ast.Node) CodeGenError!void {
        const var_decl = node.data.variable_declaration;

        const var_type = var_decl.var_type orelse .i32;
        const llvm_type = self.typeToLLVMType(var_type);

        // Create alloca for the variable
        const var_name_cstr = try std.fmt.allocPrintZ(self.allocator, "{s}", .{var_decl.name});
        defer self.allocator.free(var_name_cstr);

        const alloca = llvm.LLVMBuildAlloca(self.builder, llvm_type, var_name_cstr.ptr);
        try self.local_variables.put(var_decl.name, alloca);

        // Initialize if there's an initializer
        if (var_decl.initializer) |initializer| {
            const init_value = try self.generateExpression(initializer);
            _ = llvm.LLVMBuildStore(self.builder, init_value, alloca);
        }
    }

    fn generateBlockStatement(self: *Self, node: *ast.Node) CodeGenError!void {
        const block = node.data.block_statement;

        for (block.statements) |stmt| {
            try self.generateStatement(stmt);
        }
    }

    fn generateReturnStatement(self: *Self, node: *ast.Node) CodeGenError!void {
        const ret_stmt = node.data.return_statement;

        if (ret_stmt.value) |value| {
            const return_value = try self.generateExpression(value);
            _ = llvm.LLVMBuildRet(self.builder, return_value);
        } else {
            _ = llvm.LLVMBuildRetVoid(self.builder);
        }
    }

    fn generateExpressionStatement(self: *Self, node: *ast.Node) CodeGenError!void {
        const expr_stmt = node.data.expression_statement;
        _ = try self.generateExpression(expr_stmt.expression);
    }

    fn generateIfStatement(self: *Self, node: *ast.Node) CodeGenError!void {
        const if_stmt = node.data.if_statement;

        const condition = try self.generateExpression(if_stmt.condition);

        const function = self.current_function.?;
        const then_block = llvm.LLVMAppendBasicBlockInContext(self.context, function, "if.then");
        const else_block = if (if_stmt.else_branch != null)
            llvm.LLVMAppendBasicBlockInContext(self.context, function, "if.else")
        else
            null;
        const merge_block = llvm.LLVMAppendBasicBlockInContext(self.context, function, "if.end");

        // Create conditional branch
        if (else_block) |else_bb| {
            _ = llvm.LLVMBuildCondBr(self.builder, condition, then_block, else_bb);
        } else {
            _ = llvm.LLVMBuildCondBr(self.builder, condition, then_block, merge_block);
        }

        // Generate then block
        llvm.LLVMPositionBuilderAtEnd(self.builder, then_block);
        try self.generateStatement(if_stmt.then_branch);
        if (llvm.LLVMGetBasicBlockTerminator(then_block) == null) {
            _ = llvm.LLVMBuildBr(self.builder, merge_block);
        }

        // Generate else block if it exists
        if (if_stmt.else_branch) |else_branch| {
            const else_bb = else_block.?;
            llvm.LLVMPositionBuilderAtEnd(self.builder, else_bb);
            try self.generateStatement(else_branch);
            if (llvm.LLVMGetBasicBlockTerminator(else_bb) == null) {
                _ = llvm.LLVMBuildBr(self.builder, merge_block);
            }
        }

        // Continue with merge block
        llvm.LLVMPositionBuilderAtEnd(self.builder, merge_block);
    }

    fn generateWhileStatement(self: *Self, node: *ast.Node) CodeGenError!void {
        const while_stmt = node.data.while_statement;

        const function = self.current_function.?;
        const loop_block = llvm.LLVMAppendBasicBlockInContext(self.context, function, "while.cond");
        const body_block = llvm.LLVMAppendBasicBlockInContext(self.context, function, "while.body");
        const end_block = llvm.LLVMAppendBasicBlockInContext(self.context, function, "while.end");

        // Jump to loop condition
        _ = llvm.LLVMBuildBr(self.builder, loop_block);

        // Generate loop condition
        llvm.LLVMPositionBuilderAtEnd(self.builder, loop_block);
        const condition = try self.generateExpression(while_stmt.condition);
        _ = llvm.LLVMBuildCondBr(self.builder, condition, body_block, end_block);

        // Generate loop body
        llvm.LLVMPositionBuilderAtEnd(self.builder, body_block);
        try self.generateStatement(while_stmt.body);
        if (llvm.LLVMGetBasicBlockTerminator(body_block) == null) {
            _ = llvm.LLVMBuildBr(self.builder, loop_block);
        }

        // Continue after loop
        llvm.LLVMPositionBuilderAtEnd(self.builder, end_block);
    }

    fn generateExpression(self: *Self, node: *ast.Node) CodeGenError!llvm.LLVMValueRef {
        return switch (node.node_type) {
            .assignment_expression => self.generateAssignmentExpression(node),
            .binary_expression => self.generateBinaryExpression(node),
            .unary_expression => self.generateUnaryExpression(node),
            .call_expression => self.generateCallExpression(node),
            .identifier => self.generateIdentifier(node),
            .number_literal => self.generateNumberLiteral(node),
            .string_literal => self.generateStringLiteral(node),
            .boolean_literal => self.generateBooleanLiteral(node),
            else => CodeGenError.InvalidOperation,
        };
    }

    fn generateAssignmentExpression(self: *Self, node: *ast.Node) CodeGenError!llvm.LLVMValueRef {
        const assign_expr = node.data.assignment_expression;

        if (assign_expr.target.node_type != .identifier) {
            return CodeGenError.InvalidOperation;
        }

        const var_name = assign_expr.target.data.identifier.name;
        const value = try self.generateExpression(assign_expr.value);

        const var_alloca = self.local_variables.get(var_name) orelse return CodeGenError.UndefinedVariable;
        _ = llvm.LLVMBuildStore(self.builder, value, var_alloca);

        return value;
    }

    fn generateBinaryExpression(self: *Self, node: *ast.Node) CodeGenError!llvm.LLVMValueRef {
        const bin_expr = node.data.binary_expression;

        const left = try self.generateExpression(bin_expr.left);
        const right = try self.generateExpression(bin_expr.right);

        return switch (bin_expr.operator) {
            .add => llvm.LLVMBuildAdd(self.builder, left, right, "add"),
            .subtract => llvm.LLVMBuildSub(self.builder, left, right, "sub"),
            .multiply => llvm.LLVMBuildMul(self.builder, left, right, "mul"),
            .divide => llvm.LLVMBuildSDiv(self.builder, left, right, "div"),
            .equal => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntPredicate.LLVMIntEQ, left, right, "eq"),
            .not_equal => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntPredicate.LLVMIntNE, left, right, "ne"),
            .less_than => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntPredicate.LLVMIntSLT, left, right, "lt"),
            .less_equal => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntPredicate.LLVMIntSLE, left, right, "le"),
            .greater_than => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntPredicate.LLVMIntSGT, left, right, "gt"),
            .greater_equal => llvm.LLVMBuildICmp(self.builder, llvm.LLVMIntPredicate.LLVMIntSGE, left, right, "ge"),
            .logical_and => llvm.LLVMBuildAnd(self.builder, left, right, "and"),
            .logical_or => llvm.LLVMBuildOr(self.builder, left, right, "or"),
        };
    }

    fn generateUnaryExpression(self: *Self, node: *ast.Node) CodeGenError!llvm.LLVMValueRef {
        const unary_expr = node.data.unary_expression;

        const operand = try self.generateExpression(unary_expr.operand);

        return switch (unary_expr.operator) {
            .minus => llvm.LLVMBuildNeg(self.builder, operand, "neg"),
            .logical_not => llvm.LLVMBuildNot(self.builder, operand, "not"),
        };
    }

    fn generateCallExpression(self: *Self, node: *ast.Node) CodeGenError!llvm.LLVMValueRef {
        const call_expr = node.data.call_expression;

        if (call_expr.function.node_type != .identifier) {
            return CodeGenError.UndefinedFunction;
        }

        const func_name = call_expr.function.data.identifier.name;
        const function = self.functions.get(func_name) orelse return CodeGenError.UndefinedFunction;

        // Generate arguments
        var args = std.ArrayList(llvm.LLVMValueRef).init(self.allocator);
        defer args.deinit();

        for (call_expr.arguments) |arg| {
            const arg_value = try self.generateExpression(arg);
            try args.append(arg_value);
        }

        const function_type = llvm.LLVMGlobalGetValueType(function);

        return llvm.LLVMBuildCall2(
            self.builder,
            function_type,
            function,
            if (args.items.len > 0) args.items.ptr else null,
            @intCast(args.items.len),
            if (llvm.LLVMGetTypeKind(llvm.LLVMGetReturnType(function_type)) == llvm.LLVMTypeKind.LLVMVoidTypeKind) "" else "call"
        );
    }

    fn generateIdentifier(self: *Self, node: *ast.Node) CodeGenError!llvm.LLVMValueRef {
        const identifier = node.data.identifier;

        const var_alloca = self.local_variables.get(identifier.name) orelse return CodeGenError.UndefinedVariable;
        return llvm.LLVMBuildLoad2(self.builder, llvm.LLVMInt32TypeInContext(self.context), var_alloca, identifier.name.ptr);
    }

    fn generateNumberLiteral(self: *Self, node: *ast.Node) CodeGenError!llvm.LLVMValueRef {
        const num_literal = node.data.number_literal;

        if (num_literal.is_integer) {
            const int_val = @as(i32, @intFromFloat(num_literal.value));
            return llvm.LLVMConstInt(llvm.LLVMInt32TypeInContext(self.context), @intCast(int_val), 1);
        } else {
            return llvm.LLVMConstReal(llvm.LLVMDoubleTypeInContext(self.context), num_literal.value);
        }
    }

    fn generateStringLiteral(self: *Self, node: *ast.Node) CodeGenError!llvm.LLVMValueRef {
        const str_literal = node.data.string_literal;

        const str_name = try std.fmt.allocPrintZ(self.allocator, ".str.{d}", .{@intFromPtr(node)});
        defer self.allocator.free(str_name);

        return llvm.LLVMBuildGlobalStringPtr(self.builder, str_literal.value.ptr, str_name.ptr);
    }

    fn generateBooleanLiteral(self: *Self, node: *ast.Node) CodeGenError!llvm.LLVMValueRef {
        const bool_literal = node.data.boolean_literal;
        return llvm.LLVMConstInt(llvm.LLVMInt1TypeInContext(self.context), if (bool_literal.value) 1 else 0, 0);
    }

    fn typeToLLVMType(self: *Self, zen_type: types.Type) llvm.LLVMTypeRef {
        return switch (zen_type) {
            .void => llvm.LLVMVoidTypeInContext(self.context),
            .i32 => llvm.LLVMInt32TypeInContext(self.context),
            .f64 => llvm.LLVMDoubleTypeInContext(self.context),
            .bool => llvm.LLVMInt1TypeInContext(self.context),
            .string => llvm.LLVMPointerTypeInContext(self.context, 0),
            .unknown => llvm.LLVMInt32TypeInContext(self.context), // Default to i32
        };
    }
};