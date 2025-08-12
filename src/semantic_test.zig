const std = @import("std");
const testing = std.testing;
const ast = @import("ast.zig");
const semantic = @import("semantic.zig");
const advanced_analysis = @import("advanced_analysis.zig");
const lexer = @import("lexer.zig");

const SemanticAnalyzer = semantic.SemanticAnalyzer;
const SymbolTable = semantic.SymbolTable;
const TypeChecker = semantic.TypeChecker;
const SemanticError = semantic.SemanticError;
const AdvancedSemanticAnalyzer = advanced_analysis.AdvancedSemanticAnalyzer;
const NullSafetyLevel = advanced_analysis.NullSafetyLevel;
const AstAllocator = ast.AstAllocator;
const Position = lexer.Position;

fn createTestPosition() Position {
    return Position{ .line = 1, .column = 1 };
}

fn createTestProgram(allocator: std.mem.Allocator) !*ast.Program {
    var ast_allocator = AstAllocator.init(allocator);
    
    const main_func = ast.FunctionDeclaration{
        .name = "main",
        .parameters = &[_]ast.Parameter{},
        .return_type = try ast_allocator.createType(.i32, createTestPosition()),
        .body = try ast_allocator.createReturnStatement(
            try ast_allocator.createLiteralExpression(.{ .integer = 0 }, createTestPosition()),
            createTestPosition()
        ),
        .position = createTestPosition(),
    };
    
    const program = try allocator.create(ast.Program);
    program.* = ast.Program{
        .functions = &[_]ast.FunctionDeclaration{main_func},
        .position = createTestPosition(),
    };
    
    return program;
}

test "semantic analyzer initialization" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &ast_allocator);
    defer analyzer.deinit();
    
    try testing.expect(analyzer.errors.items.len == 0);
    try testing.expect(analyzer.current_function == null);
}

test "symbol table basic operations" {
    const allocator = testing.allocator;
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    const int_type = try ast_allocator.createType(.i32, createTestPosition());
    const symbol = semantic.SymbolInfo.init("test_var", int_type, .variable, createTestPosition());
    
    try symbol_table.defineSymbol(symbol);
    
    const found_symbol = symbol_table.lookupSymbol("test_var");
    try testing.expect(found_symbol != null);
    try testing.expectEqualStrings("test_var", found_symbol.?.name);
    try testing.expect(found_symbol.?.symbol_type.kind == .i32);
}

test "symbol table scoping" {
    const allocator = testing.allocator;
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    const int_type = try ast_allocator.createType(.i32, createTestPosition());
    
    const global_symbol = semantic.SymbolInfo.init("global_var", int_type, .variable, createTestPosition());
    try symbol_table.defineSymbol(global_symbol);
    
    try symbol_table.enterScope();
    
    const local_symbol = semantic.SymbolInfo.init("local_var", int_type, .variable, createTestPosition());
    try symbol_table.defineSymbol(local_symbol);
    
    try testing.expect(symbol_table.lookupSymbol("global_var") != null);
    try testing.expect(symbol_table.lookupSymbol("local_var") != null);
    
    try symbol_table.exitScope();
    
    try testing.expect(symbol_table.lookupSymbol("global_var") != null);
    try testing.expect(symbol_table.lookupSymbol("local_var") == null);
}

test "symbol redefinition error" {
    const allocator = testing.allocator;
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    const int_type = try ast_allocator.createType(.i32, createTestPosition());
    const symbol1 = semantic.SymbolInfo.init("test_var", int_type, .variable, createTestPosition());
    const symbol2 = semantic.SymbolInfo.init("test_var", int_type, .variable, createTestPosition());
    
    try symbol_table.defineSymbol(symbol1);
    try testing.expectError(SemanticError.RedefinedSymbol, symbol_table.defineSymbol(symbol2));
}

test "type checker compatibility" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var type_checker = TypeChecker.init(allocator, &ast_allocator);
    
    const int_type1 = try ast_allocator.createType(.i32, createTestPosition());
    const int_type2 = try ast_allocator.createType(.i32, createTestPosition());
    const float_type = try ast_allocator.createType(.f64, createTestPosition());
    
    try testing.expect(type_checker.areTypesCompatible(int_type1, int_type2));
    try testing.expect(type_checker.canImplicitlyConvert(int_type1, float_type));
    try testing.expect(!type_checker.areTypesCompatible(int_type1, float_type));
}

test "type inference for literals" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    var type_checker = TypeChecker.init(allocator, &ast_allocator);
    
    const int_expr = try ast_allocator.createLiteralExpression(.{ .integer = 42 }, createTestPosition());
    const float_expr = try ast_allocator.createLiteralExpression(.{ .float = 3.14 }, createTestPosition());
    const bool_expr = try ast_allocator.createLiteralExpression(.{ .boolean = true }, createTestPosition());
    const string_expr = try ast_allocator.createLiteralExpression(.{ .string = "hello" }, createTestPosition());
    
    const int_type = try type_checker.inferType(int_expr, &symbol_table);
    const float_type = try type_checker.inferType(float_expr, &symbol_table);
    const bool_type = try type_checker.inferType(bool_expr, &symbol_table);
    const string_type = try type_checker.inferType(string_expr, &symbol_table);
    
    try testing.expect(int_type.kind == .i32);
    try testing.expect(float_type.kind == .f64);
    try testing.expect(bool_type.kind == .bool);
    try testing.expect(string_type.kind == .string);
}

test "undefined variable error" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &ast_allocator);
    defer analyzer.deinit();
    
    const undefined_var = try ast_allocator.createIdentifierExpression("undefined_var", createTestPosition());
    
    try analyzer.analyzeExpression(undefined_var);
    
    try testing.expect(analyzer.errors.items.len == 1);
    try testing.expect(analyzer.errors.items[0].error_type == SemanticError.UndefinedVariable);
}

test "type mismatch in binary expression" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &ast_allocator);
    defer analyzer.deinit();
    
    const int_literal = try ast_allocator.createLiteralExpression(.{ .integer = 5 }, createTestPosition());
    const string_literal = try ast_allocator.createLiteralExpression(.{ .string = "hello" }, createTestPosition());
    
    const binary_expr = try ast_allocator.createBinaryExpression(
        int_literal,
        .add,
        string_literal,
        createTestPosition()
    );
    
    try analyzer.analyzeExpression(binary_expr);
    
    try testing.expect(analyzer.errors.items.len == 1);
    try testing.expect(analyzer.errors.items[0].error_type == SemanticError.TypeMismatch);
}

test "function call with wrong argument count" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &ast_allocator);
    defer analyzer.deinit();
    
    const param_type = try ast_allocator.createType(.i32, createTestPosition());
    const param = ast.Parameter{
        .name = "x",
        .param_type = param_type,
        .position = createTestPosition(),
    };
    
    var func_decl = ast.FunctionDeclaration{
        .name = "test_func",
        .parameters = &[_]ast.Parameter{param},
        .return_type = try ast_allocator.createType(.i32, createTestPosition()),
        .body = try ast_allocator.createReturnStatement(
            try ast_allocator.createLiteralExpression(.{ .integer = 0 }, createTestPosition()),
            createTestPosition()
        ),
        .position = createTestPosition(),
    };
    
    try analyzer.symbol_table.defineFunction(&func_decl);
    
    const func_call = try ast_allocator.createCallExpression(
        try ast_allocator.createIdentifierExpression("test_func", createTestPosition()),
        &[_]*ast.Expression{}, // No arguments, but function expects one
        createTestPosition()
    );
    
    try analyzer.analyzeExpression(func_call);
    
    try testing.expect(analyzer.errors.items.len == 1);
    try testing.expect(analyzer.errors.items[0].error_type == SemanticError.InvalidFunctionCall);
}

test "return type mismatch" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &ast_allocator);
    defer analyzer.deinit();
    
    const func_context = try allocator.create(semantic.FunctionContext);
    func_context.* = semantic.FunctionContext.init(
        allocator,
        undefined,
        try ast_allocator.createType(.i32, createTestPosition())
    );
    defer {
        func_context.deinit();
        allocator.destroy(func_context);
    }
    
    analyzer.current_function = func_context;
    
    const string_return = try ast_allocator.createReturnStatement(
        try ast_allocator.createLiteralExpression(.{ .string = "hello" }, createTestPosition()),
        createTestPosition()
    );
    
    const var_decl = ast.VariableDeclaration{
        .is_const = false,
        .name = "dummy",
        .type_annotation = null,
        .initializer = try ast_allocator.createLiteralExpression(.{ .string = "hello" }, createTestPosition()),
        .position = createTestPosition(),
    };
    
    try analyzer.analyzeVariableDeclaration(var_decl);
    try analyzer.analyzeReturnStatement(string_return.data.return_statement, string_return.position);
    
    try testing.expect(analyzer.errors.items.len >= 1);
    var found_type_mismatch = false;
    for (analyzer.errors.items) |error_info| {
        if (error_info.error_type == SemanticError.TypeMismatch) {
            found_type_mismatch = true;
            break;
        }
    }
    try testing.expect(found_type_mismatch);
}

test "const assignment error" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &ast_allocator);
    defer analyzer.deinit();
    
    const int_type = try ast_allocator.createType(.i32, createTestPosition());
    var symbol = semantic.SymbolInfo.init("const_var", int_type, .variable, createTestPosition());
    symbol.is_const = true;
    
    try analyzer.symbol_table.defineSymbol(symbol);
    
    const assignment = try ast_allocator.createAssignmentExpression(
        try ast_allocator.createIdentifierExpression("const_var", createTestPosition()),
        .assign,
        try ast_allocator.createLiteralExpression(.{ .integer = 10 }, createTestPosition()),
        createTestPosition()
    );
    
    try analyzer.analyzeExpression(assignment);
    
    try testing.expect(analyzer.errors.items.len == 1);
    try testing.expect(analyzer.errors.items[0].error_type == SemanticError.InvalidAssignment);
}

test "array bounds checking - negative index" {
    const allocator = testing.allocator;
    var bounds_checker = advanced_analysis.ArrayBoundsChecker.init(allocator);
    defer bounds_checker.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    const array_expr = try ast_allocator.createIdentifierExpression("test_array", createTestPosition());
    const index_expr = try ast_allocator.createLiteralExpression(.{ .integer = -1 }, createTestPosition());
    
    const array_access = struct {
        array: *ast.Expression,
        index: *ast.Expression,
        
        pub fn init(arr: *ast.Expression, idx: *ast.Expression) @This() {
            return @This(){
                .array = arr,
                .index = idx,
            };
        }
    }.init(array_expr, index_expr);
    
    const result = try bounds_checker.analyzeArrayAccess(array_access, createTestPosition());
    
    try testing.expect(result == .definitely_unsafe);
    try testing.expect(bounds_checker.warnings.items.len == 1);
    try testing.expect(bounds_checker.warnings.items[0].error_type == SemanticError.ArrayBoundsError);
}

test "array bounds checking - out of bounds" {
    const allocator = testing.allocator;
    var bounds_checker = advanced_analysis.ArrayBoundsChecker.init(allocator);
    defer bounds_checker.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    try bounds_checker.trackArrayDeclaration("test_array", 5);
    
    const array_expr = try ast_allocator.createIdentifierExpression("test_array", createTestPosition());
    const index_expr = try ast_allocator.createLiteralExpression(.{ .integer = 5 }, createTestPosition());
    
    const array_access = struct {
        array: *ast.Expression,
        index: *ast.Expression,
        
        pub fn init(arr: *ast.Expression, idx: *ast.Expression) @This() {
            return @This(){
                .array = arr,
                .index = idx,
            };
        }
    }.init(array_expr, index_expr);
    
    const result = try bounds_checker.analyzeArrayAccess(array_access, createTestPosition());
    
    try testing.expect(result == .definitely_unsafe);
    try testing.expect(bounds_checker.warnings.items.len == 1);
}

test "array bounds checking - safe access" {
    const allocator = testing.allocator;
    var bounds_checker = advanced_analysis.ArrayBoundsChecker.init(allocator);
    defer bounds_checker.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    try bounds_checker.trackArrayDeclaration("test_array", 5);
    
    const array_expr = try ast_allocator.createIdentifierExpression("test_array", createTestPosition());
    const index_expr = try ast_allocator.createLiteralExpression(.{ .integer = 2 }, createTestPosition());
    
    const array_access = struct {
        array: *ast.Expression,
        index: *ast.Expression,
        
        pub fn init(arr: *ast.Expression, idx: *ast.Expression) @This() {
            return @This(){
                .array = arr,
                .index = idx,
            };
        }
    }.init(array_expr, index_expr);
    
    const result = try bounds_checker.analyzeArrayAccess(array_access, createTestPosition());
    
    try testing.expect(result == .safe);
    try testing.expect(bounds_checker.warnings.items.len == 0);
}

test "null safety analysis - null dereference warning" {
    const allocator = testing.allocator;
    var null_analyzer = advanced_analysis.NullSafetyAnalyzer.init(allocator, .warnings);
    defer null_analyzer.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    const optional_type = try ast_allocator.createType(.optional, createTestPosition());
    optional_type.element_type = try ast_allocator.createType(.i32, createTestPosition());
    
    try null_analyzer.null_tracked_vars.put("nullable_var", true); // Mark as potentially null
    
    const identifier_expr = try ast_allocator.createIdentifierExpression("nullable_var", createTestPosition());
    identifier_expr.type_annotation = optional_type;
    
    try null_analyzer.analyzeExpression(identifier_expr, &symbol_table);
    
    try testing.expect(null_analyzer.warnings.items.len == 1);
    try testing.expect(null_analyzer.warnings.items[0].error_type == SemanticError.NullDereference);
}

test "memory lifecycle analysis - stack variable return" {
    const allocator = testing.allocator;
    var memory_analyzer = advanced_analysis.MemoryLifecycleAnalyzer.init(allocator);
    defer memory_analyzer.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    const var_decl = ast.VariableDeclaration{
        .is_const = false,
        .name = "local_var",
        .type_annotation = try ast_allocator.createType(.i32, createTestPosition()),
        .initializer = try ast_allocator.createLiteralExpression(.{ .integer = 42 }, createTestPosition()),
        .position = createTestPosition(),
    };
    
    try memory_analyzer.analyzeVariableDeclaration(var_decl);
    
    const return_expr = try ast_allocator.createIdentifierExpression("local_var", createTestPosition());
    try memory_analyzer.analyzeReturn(return_expr);
    
    try testing.expect(memory_analyzer.warnings.items.len == 1);
    try testing.expect(memory_analyzer.warnings.items[0].error_type == SemanticError.OutOfMemory);
}

test "dependency resolution - circular dependency" {
    const allocator = testing.allocator;
    var resolver = advanced_analysis.DependencyResolver.init(allocator);
    defer resolver.deinit();
    
    try resolver.addDependency("funcA", "funcB");
    try resolver.addDependency("funcB", "funcC");
    try resolver.addDependency("funcC", "funcA");
    
    const circular_deps = try resolver.checkCircularDependencies();
    defer allocator.free(circular_deps);
    
    try testing.expect(circular_deps.len > 0);
    try testing.expect(circular_deps[0].error_type == SemanticError.RecursionDepthExceeded);
}

test "advanced semantic analyzer integration" {
    const allocator = testing.allocator;
    var advanced_analyzer = AdvancedSemanticAnalyzer.init(allocator, .warnings);
    defer advanced_analyzer.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    const program = try createTestProgram(allocator);
    defer allocator.destroy(program);
    
    const errors = try advanced_analyzer.analyze(program, &symbol_table);
    defer allocator.free(errors);
    
    // Should complete without crashing - specific error count depends on implementation
}

test "dead code detection after return" {
    const allocator = testing.allocator;
    var dead_code_analyzer = semantic.DeadCodeAnalyzer.init(allocator);
    defer dead_code_analyzer.deinit();
    
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    const return_stmt = try ast_allocator.createReturnStatement(
        try ast_allocator.createLiteralExpression(.{ .integer = 0 }, createTestPosition()),
        createTestPosition()
    );
    
    const unreachable_stmt = try ast_allocator.createExpressionStatement(
        try ast_allocator.createLiteralExpression(.{ .integer = 42 }, createTestPosition())
    );
    
    const statements = [_]*ast.Statement{ return_stmt, unreachable_stmt };
    
    const has_return = try dead_code_analyzer.analyzeBlock(&statements);
    
    try testing.expect(has_return);
    try testing.expect(dead_code_analyzer.warnings.items.len == 1);
    try testing.expect(dead_code_analyzer.warnings.items[0].error_type == SemanticError.UnreachableCode);
}

test "type inference for array literals" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    var type_checker = TypeChecker.init(allocator, &ast_allocator);
    
    const elements = [_]*ast.Expression{
        try ast_allocator.createLiteralExpression(.{ .integer = 1 }, createTestPosition()),
        try ast_allocator.createLiteralExpression(.{ .integer = 2 }, createTestPosition()),
        try ast_allocator.createLiteralExpression(.{ .integer = 3 }, createTestPosition()),
    };
    
    const array_literal = try ast_allocator.createArrayLiteralExpression(&elements, createTestPosition());
    
    const inferred_type = try type_checker.inferType(array_literal, &symbol_table);
    
    try testing.expect(inferred_type.kind == .array);
    try testing.expect(inferred_type.element_type != null);
    try testing.expect(inferred_type.element_type.?.kind == .i32);
}

test "type inference for mixed array literals should fail" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var symbol_table = try SymbolTable.init(allocator);
    defer symbol_table.deinit();
    
    var type_checker = TypeChecker.init(allocator, &ast_allocator);
    
    const elements = [_]*ast.Expression{
        try ast_allocator.createLiteralExpression(.{ .integer = 1 }, createTestPosition()),
        try ast_allocator.createLiteralExpression(.{ .string = "hello" }, createTestPosition()),
    };
    
    const array_literal = try ast_allocator.createArrayLiteralExpression(&elements, createTestPosition());
    
    try testing.expectError(SemanticError.TypeMismatch, type_checker.inferType(array_literal, &symbol_table));
}

test "function parameter type checking" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &ast_allocator);
    defer analyzer.deinit();
    
    const param_type = try ast_allocator.createType(.i32, createTestPosition());
    const param = ast.Parameter{
        .name = "x",
        .param_type = param_type,
        .position = createTestPosition(),
    };
    
    var func_decl = ast.FunctionDeclaration{
        .name = "test_func",
        .parameters = &[_]ast.Parameter{param},
        .return_type = try ast_allocator.createType(.i32, createTestPosition()),
        .body = try ast_allocator.createReturnStatement(
            try ast_allocator.createLiteralExpression(.{ .integer = 0 }, createTestPosition()),
            createTestPosition()
        ),
        .position = createTestPosition(),
    };
    
    try analyzer.symbol_table.defineFunction(&func_decl);
    
    const wrong_type_arg = try ast_allocator.createLiteralExpression(.{ .string = "hello" }, createTestPosition());
    const arguments = [_]*ast.Expression{wrong_type_arg};
    
    const func_call = try ast_allocator.createCallExpression(
        try ast_allocator.createIdentifierExpression("test_func", createTestPosition()),
        &arguments,
        createTestPosition()
    );
    
    try analyzer.analyzeExpression(func_call);
    
    try testing.expect(analyzer.errors.items.len >= 1);
    var found_type_mismatch = false;
    for (analyzer.errors.items) |error_info| {
        if (error_info.error_type == SemanticError.TypeMismatch) {
            found_type_mismatch = true;
            break;
        }
    }
    try testing.expect(found_type_mismatch);
}

test "recursive function call detection" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &ast_allocator);
    defer analyzer.deinit();
    
    analyzer.recursion_limit = 2; // Set low limit for testing
    
    var func_decl = ast.FunctionDeclaration{
        .name = "recursive_func",
        .parameters = &[_]ast.Parameter{},
        .return_type = try ast_allocator.createType(.void, createTestPosition()),
        .body = try ast_allocator.createReturnStatement(null, createTestPosition()),
        .position = createTestPosition(),
    };
    
    const func_context = try allocator.create(semantic.FunctionContext);
    func_context.* = semantic.FunctionContext.init(allocator, &func_decl, null);
    func_context.recursion_depth = 3; // Exceed limit
    defer {
        func_context.deinit();
        allocator.destroy(func_context);
    }
    
    analyzer.current_function = func_context;
    
    try analyzer.symbol_table.defineFunction(&func_decl);
    
    const recursive_call = try ast_allocator.createCallExpression(
        try ast_allocator.createIdentifierExpression("recursive_func", createTestPosition()),
        &[_]*ast.Expression{},
        createTestPosition()
    );
    
    try analyzer.analyzeExpression(recursive_call);
    
    try testing.expect(analyzer.errors.items.len == 1);
    try testing.expect(analyzer.errors.items[0].error_type == SemanticError.RecursionDepthExceeded);
}

test "complete program analysis" {
    const allocator = testing.allocator;
    var ast_allocator = AstAllocator.init(allocator);
    defer ast_allocator.deinit();
    
    var analyzer = try SemanticAnalyzer.init(allocator, &ast_allocator);
    defer analyzer.deinit();
    
    const program = try createTestProgram(allocator);
    defer allocator.destroy(program);
    
    const errors = try analyzer.analyze(program);
    defer allocator.free(errors);
    
    // Basic program should analyze without major errors
    // Specific error count depends on unused symbol warnings, etc.
}