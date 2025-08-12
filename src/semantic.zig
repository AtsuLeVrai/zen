const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const HashMap = std.HashMap;
const AutoHashMap = std.AutoHashMap;
const Position = lexer.Position;
const Type = ast.Type;
const TypeKind = ast.TypeKind;
const Expression = ast.Expression;
const Statement = ast.Statement;
const Program = ast.Program;
const FunctionDeclaration = ast.FunctionDeclaration;
const VariableDeclaration = ast.VariableDeclaration;
const BinaryOp = ast.BinaryOp;
const UnaryOp = ast.UnaryOp;

pub const SemanticError = error{
    TypeMismatch,
    UndefinedVariable,
    UndefinedFunction,
    RedefinedSymbol,
    InvalidAssignment,
    InvalidFunctionCall,
    MissingReturnValue,
    UnreachableCode,
    ArrayBoundsError,
    NullDereference,
    RecursionDepthExceeded,
    ImportError,
    OutOfMemory,
};

pub const ErrorSeverity = enum {
    error_,
    warning,
    note,
};

pub const SemanticErrorInfo = struct {
    error_type: SemanticError,
    message: []const u8,
    position: Position,
    severity: ErrorSeverity,
    help_text: ?[]const u8 = null,
    related_positions: []const Position = &.{},
};

pub const SymbolKind = enum {
    variable,
    function,
    parameter,
    type_alias,
};

pub const SymbolInfo = struct {
    name: []const u8,
    symbol_type: *Type,
    kind: SymbolKind,
    position: Position,
    is_const: bool = false,
    is_used: bool = false,
    is_initialized: bool = false,
    scope_depth: u32 = 0,
    
    pub fn init(name: []const u8, symbol_type: *Type, kind: SymbolKind, position: Position) SymbolInfo {
        return SymbolInfo{
            .name = name,
            .symbol_type = symbol_type,
            .kind = kind,
            .position = position,
        };
    }
};

pub const Scope = struct {
    symbols: AutoHashMap([]const u8, SymbolInfo),
    parent: ?*Scope,
    depth: u32,
    function_context: ?*FunctionContext = null,
    
    pub fn init(allocator: Allocator, parent: ?*Scope) Scope {
        const depth = if (parent) |p| p.depth + 1 else 0;
        return Scope{
            .symbols = AutoHashMap([]const u8, SymbolInfo).init(allocator),
            .parent = parent,
            .depth = depth,
        };
    }
    
    pub fn deinit(self: *Scope) void {
        self.symbols.deinit();
    }
    
    pub fn define(self: *Scope, symbol: SymbolInfo) !void {
        try self.symbols.put(symbol.name, symbol);
    }
    
    pub fn lookup(self: *const Scope, name: []const u8) ?SymbolInfo {
        if (self.symbols.get(name)) |symbol| {
            return symbol;
        }
        
        if (self.parent) |parent| {
            return parent.lookup(name);
        }
        
        return null;
    }
    
    pub fn lookupLocal(self: *const Scope, name: []const u8) ?SymbolInfo {
        return self.symbols.get(name);
    }
    
    pub fn markUsed(self: *Scope, name: []const u8) void {
        if (self.symbols.getPtr(name)) |symbol| {
            symbol.is_used = true;
            return;
        }
        
        if (self.parent) |parent| {
            parent.markUsed(name);
        }
    }
};

pub const FunctionContext = struct {
    declaration: *const FunctionDeclaration,
    return_type: ?*Type,
    has_return_statement: bool = false,
    all_paths_return: bool = false,
    recursion_depth: u32 = 0,
    call_stack: ArrayList([]const u8),
    
    pub fn init(allocator: Allocator, declaration: *const FunctionDeclaration, return_type: ?*Type) FunctionContext {
        return FunctionContext{
            .declaration = declaration,
            .return_type = return_type,
            .call_stack = ArrayList([]const u8).init(allocator),
        };
    }
    
    pub fn deinit(self: *FunctionContext) void {
        self.call_stack.deinit();
    }
};

pub const SymbolTable = struct {
    allocator: Allocator,
    current_scope: *Scope,
    global_scope: *Scope,
    functions: AutoHashMap([]const u8, *FunctionDeclaration),
    scope_stack: ArrayList(*Scope),
    
    pub fn init(allocator: Allocator) !SymbolTable {
        var scope_stack = ArrayList(*Scope).init(allocator);
        const global_scope = try allocator.create(Scope);
        global_scope.* = Scope.init(allocator, null);
        try scope_stack.append(global_scope);
        
        return SymbolTable{
            .allocator = allocator,
            .current_scope = global_scope,
            .global_scope = global_scope,
            .functions = AutoHashMap([]const u8, *FunctionDeclaration).init(allocator),
            .scope_stack = scope_stack,
        };
    }
    
    pub fn deinit(self: *SymbolTable) void {
        for (self.scope_stack.items) |scope| {
            scope.deinit();
            self.allocator.destroy(scope);
        }
        self.scope_stack.deinit();
        self.functions.deinit();
    }
    
    pub fn enterScope(self: *SymbolTable) !void {
        const new_scope = try self.allocator.create(Scope);
        new_scope.* = Scope.init(self.allocator, self.current_scope);
        try self.scope_stack.append(new_scope);
        self.current_scope = new_scope;
    }
    
    pub fn exitScope(self: *SymbolTable) !void {
        if (self.scope_stack.items.len <= 1) {
            return error.InvalidScope;
        }
        
        const old_scope = self.scope_stack.pop();
        self.current_scope = self.scope_stack.items[self.scope_stack.items.len - 1];
        old_scope.deinit();
        self.allocator.destroy(old_scope);
    }
    
    pub fn defineSymbol(self: *SymbolTable, symbol: SymbolInfo) !void {
        if (self.current_scope.lookupLocal(symbol.name)) |_| {
            return SemanticError.RedefinedSymbol;
        }
        
        var new_symbol = symbol;
        new_symbol.scope_depth = self.current_scope.depth;
        try self.current_scope.define(new_symbol);
    }
    
    pub fn lookupSymbol(self: *SymbolTable, name: []const u8) ?SymbolInfo {
        return self.current_scope.lookup(name);
    }
    
    pub fn markSymbolUsed(self: *SymbolTable, name: []const u8) void {
        self.current_scope.markUsed(name);
    }
    
    pub fn defineFunction(self: *SymbolTable, func: *FunctionDeclaration) !void {
        if (self.functions.contains(func.name)) {
            return SemanticError.RedefinedSymbol;
        }
        try self.functions.put(func.name, func);
    }
    
    pub fn lookupFunction(self: *SymbolTable, name: []const u8) ?*FunctionDeclaration {
        return self.functions.get(name);
    }
};

pub const TypeChecker = struct {
    allocator: Allocator,
    ast_allocator: *ast.AstAllocator,
    
    pub fn init(allocator: Allocator, ast_allocator: *ast.AstAllocator) TypeChecker {
        return TypeChecker{
            .allocator = allocator,
            .ast_allocator = ast_allocator,
        };
    }
    
    pub fn areTypesCompatible(self: *TypeChecker, left: *Type, right: *Type) bool {
        if (left.kind != right.kind) {
            return self.canImplicitlyConvert(left, right);
        }
        
        switch (left.kind) {
            .optional => {
                if (left.element_type == null or right.element_type == null) {
                    return false;
                }
                return self.areTypesCompatible(left.element_type.?, right.element_type.?);
            },
            .array => {
                if (left.element_type == null or right.element_type == null) {
                    return false;
                }
                return self.areTypesCompatible(left.element_type.?, right.element_type.?);
            },
            .custom => {
                if (left.name == null or right.name == null) {
                    return false;
                }
                return std.mem.eql(u8, left.name.?, right.name.?);
            },
            else => return true,
        }
    }
    
    pub fn canImplicitlyConvert(self: *TypeChecker, from: *Type, to: *Type) bool {
        _ = self;
        
        if (from.kind == .i32 and to.kind == .f64) return true;
        
        if (from.kind != .void and to.kind == .optional) {
            if (to.element_type) |element_type| {
                return from.kind == element_type.kind;
            }
        }
        
        return false;
    }
    
    pub fn inferType(self: *TypeChecker, expr: *Expression, symbol_table: *SymbolTable) !*Type {
        return switch (expr.kind) {
            .literal => try self.inferLiteralType(expr.data.literal),
            .identifier => try self.inferIdentifierType(expr.data.identifier, symbol_table),
            .binary => try self.inferBinaryType(expr.data.binary, symbol_table),
            .unary => try self.inferUnaryType(expr.data.unary, symbol_table),
            .call => try self.inferCallType(expr.data.call, symbol_table),
            .member_access => try self.inferMemberAccessType(expr.data.member_access, symbol_table),
            .array_access => try self.inferArrayAccessType(expr.data.array_access, symbol_table),
            .array_literal => try self.inferArrayLiteralType(expr.data.array_literal, symbol_table),
            else => return error.InvalidExpression,
        };
    }
    
    fn inferLiteralType(self: *TypeChecker, literal: ast.LiteralValue) !*Type {
        const type_kind: TypeKind = switch (literal) {
            .integer => .i32,
            .float => .f64,
            .string => .string,
            .boolean => .bool,
            .null_value => .void,
        };
        
        return try self.ast_allocator.createType(type_kind, .{ .line = 0, .column = 0 });
    }
    
    fn inferIdentifierType(self: *TypeChecker, name: []const u8, symbol_table: *SymbolTable) !*Type {
        _ = self;
        if (symbol_table.lookupSymbol(name)) |symbol| {
            symbol_table.markSymbolUsed(name);
            return symbol.symbol_type;
        }
        return error.UndefinedVariable;
    }
    
    fn inferBinaryType(self: *TypeChecker, binary: anytype, symbol_table: *SymbolTable) !*Type {
        const left_type = try self.inferType(binary.left, symbol_table);
        const right_type = try self.inferType(binary.right, symbol_table);
        
        if (!self.areTypesCompatible(left_type, right_type)) {
            return error.TypeMismatch;
        }
        
        return switch (binary.operator) {
            .add, .subtract, .multiply, .divide, .modulo => left_type,
            .equal, .not_equal, .less_than, .less_equal, .greater_than, .greater_equal, .logical_and, .logical_or => try self.ast_allocator.createType(.bool, .{ .line = 0, .column = 0 }),
        };
    }
    
    fn inferUnaryType(self: *TypeChecker, unary: anytype, symbol_table: *SymbolTable) !*Type {
        const operand_type = try self.inferType(unary.operand, symbol_table);
        
        return switch (unary.operator) {
            .minus => if (operand_type.kind == .i32 or operand_type.kind == .f64) operand_type else error.TypeMismatch,
            .logical_not => if (operand_type.kind == .bool) operand_type else error.TypeMismatch,
        };
    }
    
    fn inferCallType(self: *TypeChecker, call: anytype, symbol_table: *SymbolTable) !*Type {
        _ = self;
        _ = call;
        _ = symbol_table;
        return error.InvalidExpression;
    }
    
    fn inferMemberAccessType(self: *TypeChecker, member_access: anytype, symbol_table: *SymbolTable) !*Type {
        _ = self;
        _ = member_access;
        _ = symbol_table;
        return error.InvalidExpression;
    }
    
    fn inferArrayAccessType(self: *TypeChecker, array_access: anytype, symbol_table: *SymbolTable) !*Type {
        const array_type = try self.inferType(array_access.array, symbol_table);
        const index_type = try self.inferType(array_access.index, symbol_table);
        
        if (index_type.kind != .i32) {
            return error.TypeMismatch;
        }
        
        if (array_type.kind != .array or array_type.element_type == null) {
            return error.TypeMismatch;
        }
        
        return array_type.element_type.?;
    }
    
    fn inferArrayLiteralType(self: *TypeChecker, elements: []const *Expression, symbol_table: *SymbolTable) !*Type {
        if (elements.len == 0) {
            return error.InvalidExpression;
        }
        
        const first_element_type = try self.inferType(elements[0], symbol_table);
        
        for (elements[1..]) |element| {
            const element_type = try self.inferType(element, symbol_table);
            if (!self.areTypesCompatible(first_element_type, element_type)) {
                return error.TypeMismatch;
            }
        }
        
        const array_type = try self.ast_allocator.createType(.array, .{ .line = 0, .column = 0 });
        array_type.element_type = first_element_type;
        return array_type;
    }
};

pub const DeadCodeAnalyzer = struct {
    allocator: Allocator,
    warnings: ArrayList(SemanticErrorInfo),
    
    pub fn init(allocator: Allocator) DeadCodeAnalyzer {
        return DeadCodeAnalyzer{
            .allocator = allocator,
            .warnings = ArrayList(SemanticErrorInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *DeadCodeAnalyzer) void {
        self.warnings.deinit();
    }
    
    pub fn analyzeStatement(self: *DeadCodeAnalyzer, stmt: *Statement) !bool {
        return switch (stmt.kind) {
            .return_statement => true,
            .block => try self.analyzeBlock(stmt.data.block.statements),
            .if_statement => try self.analyzeIfStatement(stmt.data.if_statement),
            .while_statement => try self.analyzeWhileStatement(stmt.data.while_statement),
            else => false,
        };
    }
    
    fn analyzeBlock(self: *DeadCodeAnalyzer, statements: []const *Statement) !bool {
        var has_return = false;
        
        for (statements, 0..) |stmt, i| {
            if (has_return) {
                _ = i;
                try self.warnings.append(SemanticErrorInfo{
                    .error_type = SemanticError.UnreachableCode,
                    .message = "Unreachable code after return statement",
                    .position = stmt.position,
                    .severity = .warning,
                });
            }
            
            if (try self.analyzeStatement(stmt)) {
                has_return = true;
            }
        }
        
        return has_return;
    }
    
    fn analyzeIfStatement(self: *DeadCodeAnalyzer, if_stmt: ast.IfStatement) !bool {
        const then_returns = try self.analyzeStatement(if_stmt.then_stmt);
        const else_returns = if (if_stmt.else_stmt) |else_stmt|
            try self.analyzeStatement(else_stmt)
        else
            false;
        
        return then_returns and else_returns;
    }
    
    fn analyzeWhileStatement(self: *DeadCodeAnalyzer, while_stmt: ast.WhileStatement) !bool {
        _ = try self.analyzeStatement(while_stmt.body);
        return false;
    }
};

pub const SemanticAnalyzer = struct {
    allocator: Allocator,
    ast_allocator: *ast.AstAllocator,
    symbol_table: SymbolTable,
    type_checker: TypeChecker,
    dead_code_analyzer: DeadCodeAnalyzer,
    errors: ArrayList(SemanticErrorInfo),
    current_function: ?*FunctionContext = null,
    recursion_limit: u32 = 100,
    
    pub fn init(allocator: Allocator, ast_allocator: *ast.AstAllocator) !SemanticAnalyzer {
        return SemanticAnalyzer{
            .allocator = allocator,
            .ast_allocator = ast_allocator,
            .symbol_table = try SymbolTable.init(allocator),
            .type_checker = TypeChecker.init(allocator, ast_allocator),
            .dead_code_analyzer = DeadCodeAnalyzer.init(allocator),
            .errors = ArrayList(SemanticErrorInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *SemanticAnalyzer) void {
        self.symbol_table.deinit();
        self.dead_code_analyzer.deinit();
        self.errors.deinit();
        if (self.current_function) |func| {
            func.deinit();
            self.allocator.destroy(func);
        }
    }
    
    pub fn analyze(self: *SemanticAnalyzer, program: *Program) ![]const SemanticErrorInfo {
        for (program.functions) |*func| {
            try self.analyzeFunction(func);
        }
        
        try self.checkUnusedSymbols();
        
        for (self.dead_code_analyzer.warnings.items) |warning| {
            try self.errors.append(warning);
        }
        
        return self.errors.toOwnedSlice();
    }
    
    fn analyzeFunction(self: *SemanticAnalyzer, func: *FunctionDeclaration) !void {
        try self.symbol_table.defineFunction(func);
        
        try self.symbol_table.enterScope();
        defer self.symbol_table.exitScope() catch {};
        
        const func_context = try self.allocator.create(FunctionContext);
        func_context.* = FunctionContext.init(self.allocator, func, func.return_type);
        defer {
            func_context.deinit();
            self.allocator.destroy(func_context);
        }
        
        self.current_function = func_context;
        
        for (func.parameters) |param| {
            const param_symbol = SymbolInfo.init(param.name, param.param_type, .parameter, param.position);
            try self.symbol_table.defineSymbol(param_symbol);
        }
        
        try self.analyzeStatement(func.body);
        
        if (!func_context.all_paths_return and func.return_type != null and func.return_type.?.kind != .void) {
            try self.errors.append(SemanticErrorInfo{
                .error_type = SemanticError.MissingReturnValue,
                .message = "Function must return a value on all code paths",
                .position = func.position,
                .severity = .error_,
            });
        }
        
        self.current_function = null;
    }
    
    fn analyzeStatement(self: *SemanticAnalyzer, stmt: *Statement) !void {
        switch (stmt.kind) {
            .expression => try self.analyzeExpression(stmt.data.expression),
            .variable_declaration => try self.analyzeVariableDeclaration(stmt.data.variable_declaration),
            .return_statement => try self.analyzeReturnStatement(stmt.data.return_statement, stmt.position),
            .if_statement => try self.analyzeIfStatement(stmt.data.if_statement),
            .while_statement => try self.analyzeWhileStatement(stmt.data.while_statement),
            .for_statement => try self.analyzeForStatement(stmt.data.for_statement),
            .switch_statement => try self.analyzeSwitchStatement(stmt.data.switch_statement),
            .block => try self.analyzeBlockStatement(stmt.data.block),
        }
    }
    
    fn analyzeExpression(self: *SemanticAnalyzer, expr: *Expression) !void {
        const inferred_type = self.type_checker.inferType(expr, &self.symbol_table) catch |err| switch (err) {
            SemanticError.UndefinedVariable => {
                if (expr.kind == .identifier) {
                    try self.errors.append(SemanticErrorInfo{
                        .error_type = SemanticError.UndefinedVariable,
                        .message = "Undefined variable",
                        .position = expr.position,
                        .severity = .error_,
                    });
                }
                return;
            },
            SemanticError.TypeMismatch => {
                try self.errors.append(SemanticErrorInfo{
                    .error_type = SemanticError.TypeMismatch,
                    .message = "Type mismatch in expression",
                    .position = expr.position,
                    .severity = .error_,
                });
                return;
            },
            else => return err,
        };
        
        expr.type_annotation = inferred_type;
        
        switch (expr.kind) {
            .binary => try self.analyzeExpression(expr.data.binary.left),
            .unary => try self.analyzeExpression(expr.data.unary.operand),
            .assignment => try self.analyzeAssignment(expr.data.assignment),
            .call => try self.analyzeFunctionCall(expr.data.call),
            .member_access => try self.analyzeExpression(expr.data.member_access.object),
            .array_access => {
                try self.analyzeExpression(expr.data.array_access.array);
                try self.analyzeExpression(expr.data.array_access.index);
            },
            .array_literal => {
                for (expr.data.array_literal) |element| {
                    try self.analyzeExpression(element);
                }
            },
            else => {},
        }
    }
    
    fn analyzeVariableDeclaration(self: *SemanticAnalyzer, var_decl: VariableDeclaration) !void {
        var symbol_type: *Type = undefined;
        
        if (var_decl.initializer) |init_expr| {
            try self.analyzeExpression(init_expr);
            
            if (var_decl.type_annotation) |declared_type| {
                const inferred_type = init_expr.type_annotation orelse return error.InvalidExpression;
                
                if (!self.type_checker.areTypesCompatible(declared_type, inferred_type)) {
                    try self.errors.append(SemanticErrorInfo{
                        .error_type = SemanticError.TypeMismatch,
                        .message = "Type annotation doesn't match initializer type",
                        .position = var_decl.position,
                        .severity = .error_,
                    });
                    return;
                }
                symbol_type = declared_type;
            } else {
                symbol_type = init_expr.type_annotation orelse return error.InvalidExpression;
            }
        } else {
            if (var_decl.type_annotation) |declared_type| {
                symbol_type = declared_type;
            } else {
                try self.errors.append(SemanticErrorInfo{
                    .error_type = SemanticError.InvalidAssignment,
                    .message = "Variable declaration must have either type annotation or initializer",
                    .position = var_decl.position,
                    .severity = .error_,
                });
                return;
            }
        }
        
        var symbol = SymbolInfo.init(var_decl.name, symbol_type, .variable, var_decl.position);
        symbol.is_const = var_decl.is_const;
        symbol.is_initialized = var_decl.initializer != null;
        
        self.symbol_table.defineSymbol(symbol) catch |err| switch (err) {
            SemanticError.RedefinedSymbol => {
                try self.errors.append(SemanticErrorInfo{
                    .error_type = SemanticError.RedefinedSymbol,
                    .message = "Symbol already defined in current scope",
                    .position = var_decl.position,
                    .severity = .error_,
                });
            },
            else => return err,
        };
    }
    
    fn analyzeReturnStatement(self: *SemanticAnalyzer, return_expr: ?*Expression, position: Position) !void {
        if (self.current_function) |func_context| {
            func_context.has_return_statement = true;
            
            if (return_expr) |expr| {
                try self.analyzeExpression(expr);
                
                if (func_context.return_type) |expected_type| {
                    const actual_type = expr.type_annotation orelse return;
                    
                    if (!self.type_checker.areTypesCompatible(expected_type, actual_type)) {
                        try self.errors.append(SemanticErrorInfo{
                            .error_type = SemanticError.TypeMismatch,
                            .message = "Return type doesn't match function signature",
                            .position = position,
                            .severity = .error_,
                        });
                    }
                } else {
                    try self.errors.append(SemanticErrorInfo{
                        .error_type = SemanticError.InvalidAssignment,
                        .message = "Void function cannot return a value",
                        .position = position,
                        .severity = .error_,
                    });
                }
            } else {
                if (func_context.return_type != null and func_context.return_type.?.kind != .void) {
                    try self.errors.append(SemanticErrorInfo{
                        .error_type = SemanticError.MissingReturnValue,
                        .message = "Function must return a value",
                        .position = position,
                        .severity = .error_,
                    });
                }
            }
        }
    }
    
    fn analyzeIfStatement(self: *SemanticAnalyzer, if_stmt: ast.IfStatement) !void {
        try self.analyzeExpression(if_stmt.condition);
        
        if (if_stmt.condition.type_annotation) |condition_type| {
            if (condition_type.kind != .bool) {
                try self.errors.append(SemanticErrorInfo{
                    .error_type = SemanticError.TypeMismatch,
                    .message = "If condition must be boolean",
                    .position = if_stmt.condition.position,
                    .severity = .error_,
                });
            }
        }
        
        try self.symbol_table.enterScope();
        defer self.symbol_table.exitScope() catch {};
        try self.analyzeStatement(if_stmt.then_stmt);
        
        if (if_stmt.else_stmt) |else_stmt| {
            try self.symbol_table.enterScope();
            defer self.symbol_table.exitScope() catch {};
            try self.analyzeStatement(else_stmt);
        }
    }
    
    fn analyzeWhileStatement(self: *SemanticAnalyzer, while_stmt: ast.WhileStatement) !void {
        try self.analyzeExpression(while_stmt.condition);
        
        if (while_stmt.condition.type_annotation) |condition_type| {
            if (condition_type.kind != .bool) {
                try self.errors.append(SemanticErrorInfo{
                    .error_type = SemanticError.TypeMismatch,
                    .message = "While condition must be boolean",
                    .position = while_stmt.condition.position,
                    .severity = .error_,
                });
            }
        }
        
        try self.symbol_table.enterScope();
        defer self.symbol_table.exitScope() catch {};
        try self.analyzeStatement(while_stmt.body);
    }
    
    fn analyzeForStatement(self: *SemanticAnalyzer, for_stmt: ast.ForStatement) !void {
        try self.symbol_table.enterScope();
        defer self.symbol_table.exitScope() catch {};
        
        if (for_stmt.init) |init_stmt| {
            try self.analyzeStatement(init_stmt);
        }
        
        if (for_stmt.condition) |condition| {
            try self.analyzeExpression(condition);
            
            if (condition.type_annotation) |condition_type| {
                if (condition_type.kind != .bool) {
                    try self.errors.append(SemanticErrorInfo{
                        .error_type = SemanticError.TypeMismatch,
                        .message = "For condition must be boolean",
                        .position = condition.position,
                        .severity = .error_,
                    });
                }
            }
        }
        
        if (for_stmt.increment) |increment| {
            try self.analyzeExpression(increment);
        }
        
        try self.analyzeStatement(for_stmt.body);
    }
    
    fn analyzeSwitchStatement(self: *SemanticAnalyzer, switch_stmt: ast.SwitchStatement) !void {
        try self.analyzeExpression(switch_stmt.expression);
        
        for (switch_stmt.cases) |case| {
            if (case.value) |value| {
                try self.analyzeExpression(value);
                
                if (switch_stmt.expression.type_annotation) |switch_type| {
                    if (value.type_annotation) |case_type| {
                        if (!self.type_checker.areTypesCompatible(switch_type, case_type)) {
                            try self.errors.append(SemanticErrorInfo{
                                .error_type = SemanticError.TypeMismatch,
                                .message = "Switch case type doesn't match switch expression type",
                                .position = case.position,
                                .severity = .error_,
                            });
                        }
                    }
                }
            }
            
            try self.symbol_table.enterScope();
            defer self.symbol_table.exitScope() catch {};
            
            for (case.statements) |stmt| {
                try self.analyzeStatement(stmt);
            }
        }
    }
    
    fn analyzeBlockStatement(self: *SemanticAnalyzer, block: ast.BlockStatement) !void {
        try self.symbol_table.enterScope();
        defer self.symbol_table.exitScope() catch {};
        
        for (block.statements) |stmt| {
            try self.analyzeStatement(stmt);
        }
        
        if (self.current_function) |func_context| {
            if (try self.dead_code_analyzer.analyzeBlock(block.statements)) {
                func_context.all_paths_return = true;
            }
        }
    }
    
    fn analyzeAssignment(self: *SemanticAnalyzer, assignment: anytype) !void {
        try self.analyzeExpression(assignment.target);
        try self.analyzeExpression(assignment.value);
        
        if (assignment.target.kind == .identifier) {
            const target_name = assignment.target.data.identifier;
            if (self.symbol_table.lookupSymbol(target_name)) |symbol| {
                if (symbol.is_const) {
                    try self.errors.append(SemanticErrorInfo{
                        .error_type = SemanticError.InvalidAssignment,
                        .message = "Cannot assign to const variable",
                        .position = assignment.target.position,
                        .severity = .error_,
                    });
                }
            }
        }
        
        if (assignment.target.type_annotation) |target_type| {
            if (assignment.value.type_annotation) |value_type| {
                if (!self.type_checker.areTypesCompatible(target_type, value_type)) {
                    try self.errors.append(SemanticErrorInfo{
                        .error_type = SemanticError.TypeMismatch,
                        .message = "Assignment type mismatch",
                        .position = assignment.value.position,
                        .severity = .error_,
                    });
                }
            }
        }
    }
    
    fn analyzeFunctionCall(self: *SemanticAnalyzer, call: anytype) !void {
        try self.analyzeExpression(call.callee);
        
        for (call.arguments) |arg| {
            try self.analyzeExpression(arg);
        }
        
        if (call.callee.kind == .identifier) {
            const func_name = call.callee.data.identifier;
            
            if (self.symbol_table.lookupFunction(func_name)) |func_decl| {
                if (call.arguments.len != func_decl.parameters.len) {
                    try self.errors.append(SemanticErrorInfo{
                        .error_type = SemanticError.InvalidFunctionCall,
                        .message = "Function call argument count mismatch",
                        .position = call.callee.position,
                        .severity = .error_,
                    });
                    return;
                }
                
                for (call.arguments, func_decl.parameters) |arg, param| {
                    if (arg.type_annotation) |arg_type| {
                        if (!self.type_checker.areTypesCompatible(param.param_type, arg_type)) {
                            try self.errors.append(SemanticErrorInfo{
                                .error_type = SemanticError.TypeMismatch,
                                .message = "Function argument type mismatch",
                                .position = arg.position,
                                .severity = .error_,
                            });
                        }
                    }
                }
                
                if (self.current_function) |func_context| {
                    if (std.mem.eql(u8, func_name, func_context.declaration.name)) {
                        func_context.recursion_depth += 1;
                        if (func_context.recursion_depth > self.recursion_limit) {
                            try self.errors.append(SemanticErrorInfo{
                                .error_type = SemanticError.RecursionDepthExceeded,
                                .message = "Maximum recursion depth exceeded",
                                .position = call.callee.position,
                                .severity = .warning,
                            });
                        }
                    }
                }
            } else {
                try self.errors.append(SemanticErrorInfo{
                    .error_type = SemanticError.UndefinedFunction,
                    .message = "Undefined function",
                    .position = call.callee.position,
                    .severity = .error_,
                });
            }
        }
    }
    
    fn checkUnusedSymbols(self: *SemanticAnalyzer) !void {
        const scope_iter = self.symbol_table.scope_stack.items;
        for (scope_iter) |scope| {
            var symbol_iter = scope.symbols.iterator();
            while (symbol_iter.next()) |entry| {
                const symbol = entry.value_ptr.*;
                if (!symbol.is_used and symbol.kind == .variable) {
                    try self.errors.append(SemanticErrorInfo{
                        .error_type = SemanticError.UndefinedVariable,
                        .message = "Unused variable",
                        .position = symbol.position,
                        .severity = .warning,
                    });
                }
            }
        }
    }
};