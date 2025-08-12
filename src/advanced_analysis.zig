const std = @import("std");
const ast = @import("ast.zig");
const semantic = @import("semantic.zig");
const lexer = @import("lexer.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const AutoHashMap = std.AutoHashMap;
const Position = lexer.Position;
const Type = ast.Type;
const TypeKind = ast.TypeKind;
const Expression = ast.Expression;
const Statement = ast.Statement;
const SemanticError = semantic.SemanticError;
const SemanticErrorInfo = semantic.SemanticErrorInfo;
const ErrorSeverity = semantic.ErrorSeverity;
const SymbolTable = semantic.SymbolTable;

pub const NullSafetyLevel = enum {
    none,
    warnings,
    strict,
};

pub const BoundsCheckResult = enum {
    safe,
    potentially_unsafe,
    definitely_unsafe,
    unknown,
};

pub const MemoryLifecycle = enum {
    stack,
    heap,
    static,
    parameter,
    unknown,
};

pub const VariableLifecycle = struct {
    name: []const u8,
    lifecycle: MemoryLifecycle,
    position: Position,
    is_borrowed: bool = false,
    borrow_count: u32 = 0,
    is_moved: bool = false,
    move_position: ?Position = null,
};

pub const NullSafetyAnalyzer = struct {
    allocator: Allocator,
    safety_level: NullSafetyLevel,
    null_tracked_vars: AutoHashMap([]const u8, bool),
    warnings: ArrayList(SemanticErrorInfo),
    
    pub fn init(allocator: Allocator, safety_level: NullSafetyLevel) NullSafetyAnalyzer {
        return NullSafetyAnalyzer{
            .allocator = allocator,
            .safety_level = safety_level,
            .null_tracked_vars = AutoHashMap([]const u8, bool).init(allocator),
            .warnings = ArrayList(SemanticErrorInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *NullSafetyAnalyzer) void {
        self.null_tracked_vars.deinit();
        self.warnings.deinit();
    }
    
    pub fn analyzeExpression(self: *NullSafetyAnalyzer, expr: *Expression, symbol_table: *SymbolTable) !void {
        switch (expr.kind) {
            .identifier => try self.analyzeIdentifier(expr),
            .binary => try self.analyzeBinaryExpression(expr, symbol_table),
            .unary => try self.analyzeUnaryExpression(expr, symbol_table),
            .assignment => try self.analyzeAssignment(expr, symbol_table),
            .call => try self.analyzeCall(expr, symbol_table),
            .member_access => try self.analyzeMemberAccess(expr, symbol_table),
            .array_access => try self.analyzeArrayAccess(expr, symbol_table),
            .literal => try self.analyzeLiteral(expr),
            else => {},
        }
    }
    
    fn analyzeIdentifier(self: *NullSafetyAnalyzer, expr: *Expression) !void {
        if (expr.kind != .identifier) return;
        
        const var_name = expr.data.identifier;
        
        if (self.isNullableType(expr.type_annotation)) {
            if (self.null_tracked_vars.get(var_name)) |is_potentially_null| {
                if (is_potentially_null and self.safety_level != .none) {
                    try self.warnings.append(SemanticErrorInfo{
                        .error_type = SemanticError.NullDereference,
                        .message = "Potential null dereference",
                        .position = expr.position,
                        .severity = if (self.safety_level == .strict) .error_ else .warning,
                        .help_text = "Consider checking for null before use",
                    });
                }
            }
        }
    }
    
    fn analyzeBinaryExpression(self: *NullSafetyAnalyzer, expr: *Expression, symbol_table: *SymbolTable) !void {
        if (expr.kind != .binary) return;
        
        const binary = expr.data.binary;
        try self.analyzeExpression(binary.left, symbol_table);
        try self.analyzeExpression(binary.right, symbol_table);
        
        switch (binary.operator) {
            .equal, .not_equal => {
                if (binary.right.kind == .literal and binary.right.data.literal == .null_value) {
                    if (binary.left.kind == .identifier) {
                        const var_name = binary.left.data.identifier;
                        const is_null_check = binary.operator == .equal;
                        try self.null_tracked_vars.put(var_name, !is_null_check);
                    }
                }
            },
            else => {},
        }
    }
    
    fn analyzeUnaryExpression(self: *NullSafetyAnalyzer, expr: *Expression, symbol_table: *SymbolTable) !void {
        if (expr.kind != .unary) return;
        try self.analyzeExpression(expr.data.unary.operand, symbol_table);
    }
    
    fn analyzeAssignment(self: *NullSafetyAnalyzer, expr: *Expression, symbol_table: *SymbolTable) !void {
        if (expr.kind != .assignment) return;
        
        const assignment = expr.data.assignment;
        try self.analyzeExpression(assignment.target, symbol_table);
        try self.analyzeExpression(assignment.value, symbol_table);
        
        if (assignment.target.kind == .identifier) {
            const var_name = assignment.target.data.identifier;
            const is_null_assignment = assignment.value.kind == .literal and 
                                     assignment.value.data.literal == .null_value;
            
            if (self.isNullableType(assignment.target.type_annotation)) {
                try self.null_tracked_vars.put(var_name, is_null_assignment);
            }
        }
    }
    
    fn analyzeCall(self: *NullSafetyAnalyzer, expr: *Expression, symbol_table: *SymbolTable) !void {
        if (expr.kind != .call) return;
        
        const call = expr.data.call;
        try self.analyzeExpression(call.callee, symbol_table);
        
        for (call.arguments) |arg| {
            try self.analyzeExpression(arg, symbol_table);
        }
    }
    
    fn analyzeMemberAccess(self: *NullSafetyAnalyzer, expr: *Expression, symbol_table: *SymbolTable) !void {
        if (expr.kind != .member_access) return;
        
        const member_access = expr.data.member_access;
        try self.analyzeExpression(member_access.object, symbol_table);
        
        if (self.isNullableType(member_access.object.type_annotation)) {
            if (member_access.object.kind == .identifier) {
                const obj_name = member_access.object.data.identifier;
                if (self.null_tracked_vars.get(obj_name)) |is_potentially_null| {
                    if (is_potentially_null and self.safety_level != .none) {
                        try self.warnings.append(SemanticErrorInfo{
                            .error_type = SemanticError.NullDereference,
                            .message = "Potential null member access",
                            .position = expr.position,
                            .severity = if (self.safety_level == .strict) .error_ else .warning,
                            .help_text = "Consider using safe navigation operator (?.)",
                        });
                    }
                }
            }
        }
    }
    
    fn analyzeArrayAccess(self: *NullSafetyAnalyzer, expr: *Expression, symbol_table: *SymbolTable) !void {
        if (expr.kind != .array_access) return;
        
        const array_access = expr.data.array_access;
        try self.analyzeExpression(array_access.array, symbol_table);
        try self.analyzeExpression(array_access.index, symbol_table);
        
        if (self.isNullableType(array_access.array.type_annotation)) {
            if (array_access.array.kind == .identifier) {
                const array_name = array_access.array.data.identifier;
                if (self.null_tracked_vars.get(array_name)) |is_potentially_null| {
                    if (is_potentially_null and self.safety_level != .none) {
                        try self.warnings.append(SemanticErrorInfo{
                            .error_type = SemanticError.NullDereference,
                            .message = "Potential null array access",
                            .position = expr.position,
                            .severity = if (self.safety_level == .strict) .error_ else .warning,
                        });
                    }
                }
            }
        }
    }
    
    fn analyzeLiteral(self: *NullSafetyAnalyzer, expr: *Expression) !void {
        _ = self;
        _ = expr;
    }
    
    pub fn analyzeStatement(self: *NullSafetyAnalyzer, stmt: *Statement, symbol_table: *SymbolTable) !void {
        switch (stmt.kind) {
            .expression => try self.analyzeExpression(stmt.data.expression, symbol_table),
            .variable_declaration => try self.analyzeVariableDeclaration(stmt.data.variable_declaration),
            .if_statement => try self.analyzeIfStatement(stmt.data.if_statement, symbol_table),
            .while_statement => try self.analyzeWhileStatement(stmt.data.while_statement, symbol_table),
            .for_statement => try self.analyzeForStatement(stmt.data.for_statement, symbol_table),
            .block => try self.analyzeBlockStatement(stmt.data.block, symbol_table),
            else => {},
        }
    }
    
    fn analyzeVariableDeclaration(self: *NullSafetyAnalyzer, var_decl: ast.VariableDeclaration) !void {
        if (self.isNullableType(var_decl.type_annotation)) {
            const is_null_init = if (var_decl.initializer) |initializer|
                initializer.kind == .literal and initializer.data.literal == .null_value
            else
                true;
            
            try self.null_tracked_vars.put(var_decl.name, is_null_init);
        }
    }
    
    fn analyzeIfStatement(self: *NullSafetyAnalyzer, if_stmt: ast.IfStatement, symbol_table: *SymbolTable) !void {
        try self.analyzeExpression(if_stmt.condition, symbol_table);
        
        const saved_state = try self.saveNullState();
        defer self.allocator.free(saved_state);
        
        try self.analyzeStatement(if_stmt.then_stmt, symbol_table);
        
        if (if_stmt.else_stmt) |else_stmt| {
            try self.restoreNullState(saved_state);
            try self.analyzeStatement(else_stmt, symbol_table);
        }
    }
    
    fn analyzeWhileStatement(self: *NullSafetyAnalyzer, while_stmt: ast.WhileStatement, symbol_table: *SymbolTable) !void {
        try self.analyzeExpression(while_stmt.condition, symbol_table);
        try self.analyzeStatement(while_stmt.body, symbol_table);
    }
    
    fn analyzeForStatement(self: *NullSafetyAnalyzer, for_stmt: ast.ForStatement, symbol_table: *SymbolTable) !void {
        if (for_stmt.init) |init_stmt| {
            try self.analyzeStatement(init_stmt, symbol_table);
        }
        
        if (for_stmt.condition) |condition| {
            try self.analyzeExpression(condition, symbol_table);
        }
        
        try self.analyzeStatement(for_stmt.body, symbol_table);
        
        if (for_stmt.increment) |increment| {
            try self.analyzeExpression(increment, symbol_table);
        }
    }
    
    fn analyzeBlockStatement(self: *NullSafetyAnalyzer, block: ast.BlockStatement, symbol_table: *SymbolTable) !void {
        for (block.statements) |stmt| {
            try self.analyzeStatement(stmt, symbol_table);
        }
    }
    
    fn isNullableType(self: *NullSafetyAnalyzer, type_opt: ?*Type) bool {
        _ = self;
        if (type_opt) |typ| {
            return typ.kind == .optional;
        }
        return false;
    }
    
    fn saveNullState(self: *NullSafetyAnalyzer) ![]NullStateEntry {
        var entries = try ArrayList(NullStateEntry).initCapacity(self.allocator, self.null_tracked_vars.count());
        
        var iter = self.null_tracked_vars.iterator();
        while (iter.next()) |entry| {
            try entries.append(NullStateEntry{
                .name = entry.key_ptr.*,
                .is_null = entry.value_ptr.*,
            });
        }
        
        return entries.toOwnedSlice();
    }
    
    fn restoreNullState(self: *NullSafetyAnalyzer, state: []const NullStateEntry) !void {
        self.null_tracked_vars.clearAndFree();
        
        for (state) |entry| {
            try self.null_tracked_vars.put(entry.name, entry.is_null);
        }
    }
};

const NullStateEntry = struct {
    name: []const u8,
    is_null: bool,
};

pub const ArrayBoundsChecker = struct {
    allocator: Allocator,
    warnings: ArrayList(SemanticErrorInfo),
    array_sizes: AutoHashMap([]const u8, ?i64),
    
    pub fn init(allocator: Allocator) ArrayBoundsChecker {
        return ArrayBoundsChecker{
            .allocator = allocator,
            .warnings = ArrayList(SemanticErrorInfo).init(allocator),
            .array_sizes = AutoHashMap([]const u8, ?i64).init(allocator),
        };
    }
    
    pub fn deinit(self: *ArrayBoundsChecker) void {
        self.warnings.deinit();
        self.array_sizes.deinit();
    }
    
    pub fn analyzeArrayAccess(self: *ArrayBoundsChecker, array_access: anytype, position: Position) !BoundsCheckResult {
        if (array_access.array.kind == .identifier and array_access.index.kind == .literal) {
            const array_name = array_access.array.data.identifier;
            const index_literal = array_access.index.data.literal;
            
            if (index_literal == .integer) {
                const index_value = index_literal.integer;
                
                if (index_value < 0) {
                    try self.warnings.append(SemanticErrorInfo{
                        .error_type = SemanticError.ArrayBoundsError,
                        .message = "Array index cannot be negative",
                        .position = position,
                        .severity = .error_,
                    });
                    return .definitely_unsafe;
                }
                
                if (self.array_sizes.get(array_name)) |size_opt| {
                    if (size_opt) |size| {
                        if (index_value >= size) {
                            try self.warnings.append(SemanticErrorInfo{
                                .error_type = SemanticError.ArrayBoundsError,
                                .message = "Array index out of bounds",
                                .position = position,
                                .severity = .error_,
                                .help_text = "Array index must be less than array size",
                            });
                            return .definitely_unsafe;
                        }
                        return .safe;
                    }
                }
                
                return .potentially_unsafe;
            }
        }
        
        return .unknown;
    }
    
    pub fn trackArrayDeclaration(self: *ArrayBoundsChecker, name: []const u8, size: ?i64) !void {
        try self.array_sizes.put(name, size);
    }
    
    pub fn analyzeArrayLiteral(self: *ArrayBoundsChecker, elements: []const *Expression) i64 {
        _ = self;
        return @intCast(elements.len);
    }
};

pub const MemoryLifecycleAnalyzer = struct {
    allocator: Allocator,
    variables: AutoHashMap([]const u8, VariableLifecycle),
    warnings: ArrayList(SemanticErrorInfo),
    optimization_hints: ArrayList(SemanticErrorInfo),
    
    pub fn init(allocator: Allocator) MemoryLifecycleAnalyzer {
        return MemoryLifecycleAnalyzer{
            .allocator = allocator,
            .variables = AutoHashMap([]const u8, VariableLifecycle).init(allocator),
            .warnings = ArrayList(SemanticErrorInfo).init(allocator),
            .optimization_hints = ArrayList(SemanticErrorInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *MemoryLifecycleAnalyzer) void {
        self.variables.deinit();
        self.warnings.deinit();
        self.optimization_hints.deinit();
    }
    
    pub fn analyzeVariableDeclaration(self: *MemoryLifecycleAnalyzer, var_decl: ast.VariableDeclaration) !void {
        const lifecycle = self.inferLifecycle(var_decl.type_annotation, var_decl.initializer);
        
        const var_lifecycle = VariableLifecycle{
            .name = var_decl.name,
            .lifecycle = lifecycle,
            .position = var_decl.position,
        };
        
        try self.variables.put(var_decl.name, var_lifecycle);
        
        if (lifecycle == .heap and !var_decl.is_const) {
            try self.optimization_hints.append(SemanticErrorInfo{
                .error_type = SemanticError.OutOfMemory,
                .message = "Consider using stack allocation if possible",
                .position = var_decl.position,
                .severity = .note,
                .help_text = "Heap allocations are slower than stack allocations",
            });
        }
    }
    
    pub fn analyzeAssignment(self: *MemoryLifecycleAnalyzer, assignment: anytype) !void {
        if (assignment.target.kind == .identifier) {
            const var_name = assignment.target.data.identifier;
            
            if (self.variables.getPtr(var_name)) |var_lifecycle| {
                if (var_lifecycle.lifecycle == .heap) {
                    if (self.isOwnershipTransfer(assignment.value)) {
                        if (var_lifecycle.is_moved) {
                            try self.warnings.append(SemanticErrorInfo{
                                .error_type = SemanticError.OutOfMemory,
                                .message = "Use after move",
                                .position = assignment.target.position,
                                .severity = .error_,
                                .help_text = "Variable was moved and cannot be used",
                                .related_positions = if (var_lifecycle.move_position) |pos| &[_]Position{pos} else &[_]Position{},
                            });
                        } else {
                            var_lifecycle.is_moved = true;
                            var_lifecycle.move_position = assignment.target.position;
                        }
                    }
                }
            }
        }
    }
    
    pub fn analyzeBorrow(self: *MemoryLifecycleAnalyzer, var_name: []const u8, position: Position) !void {
        if (self.variables.getPtr(var_name)) |var_lifecycle| {
            if (var_lifecycle.is_moved) {
                try self.warnings.append(SemanticErrorInfo{
                    .error_type = SemanticError.OutOfMemory,
                    .message = "Cannot borrow moved value",
                    .position = position,
                    .severity = .error_,
                    .related_positions = if (var_lifecycle.move_position) |pos| &[_]Position{pos} else &[_]Position{},
                });
            } else {
                var_lifecycle.is_borrowed = true;
                var_lifecycle.borrow_count += 1;
            }
        }
    }
    
    pub fn analyzeReturn(self: *MemoryLifecycleAnalyzer, return_expr: ?*Expression) !void {
        if (return_expr) |expr| {
            if (expr.kind == .identifier) {
                const var_name = expr.data.identifier;
                if (self.variables.get(var_name)) |var_lifecycle| {
                    if (var_lifecycle.lifecycle == .stack) {
                        try self.warnings.append(SemanticErrorInfo{
                            .error_type = SemanticError.OutOfMemory,
                            .message = "Returning reference to local variable",
                            .position = expr.position,
                            .severity = .error_,
                            .help_text = "Local variables are destroyed when function returns",
                        });
                    }
                }
            }
        }
    }
    
    pub fn generateOptimizationHints(self: *MemoryLifecycleAnalyzer) !void {
        var iter = self.variables.iterator();
        while (iter.next()) |entry| {
            const var_lifecycle = entry.value_ptr.*;
            
            if (var_lifecycle.lifecycle == .stack and var_lifecycle.borrow_count == 0) {
                try self.optimization_hints.append(SemanticErrorInfo{
                    .error_type = SemanticError.OutOfMemory,
                    .message = "Variable never borrowed, consider moving instead of copying",
                    .position = var_lifecycle.position,
                    .severity = .note,
                });
            }
            
            if (var_lifecycle.lifecycle == .heap and var_lifecycle.borrow_count > 10) {
                try self.optimization_hints.append(SemanticErrorInfo{
                    .error_type = SemanticError.OutOfMemory,
                    .message = "High borrow count detected, consider reference counting",
                    .position = var_lifecycle.position,
                    .severity = .note,
                });
            }
        }
    }
    
    fn inferLifecycle(self: *MemoryLifecycleAnalyzer, type_annotation: ?*Type, initializer: ?*Expression) MemoryLifecycle {
        _ = self;
        
        if (type_annotation) |typ| {
            switch (typ.kind) {
                .array => return .heap,
                .string => return .heap,
                .custom => return .heap,
                else => {},
            }
        }
        
        if (initializer) |init_expr| {
            switch (init_expr.kind) {
                .array_literal => return .heap,
                .literal => |lit| switch (lit) {
                    .string => return .static,
                    else => return .stack,
                },
                .call => return .heap,
                else => return .stack,
            }
        }
        
        return .stack;
    }
    
    fn isOwnershipTransfer(self: *MemoryLifecycleAnalyzer, expr: *Expression) bool {
        _ = self;
        return switch (expr.kind) {
            .call => true,
            .array_literal => true,
            .identifier => false,
            else => false,
        };
    }
};

pub const DependencyResolver = struct {
    allocator: Allocator,
    dependencies: AutoHashMap([]const u8, ArrayList([]const u8)),
    circular_deps: ArrayList(SemanticErrorInfo),
    
    pub fn init(allocator: Allocator) DependencyResolver {
        return DependencyResolver{
            .allocator = allocator,
            .dependencies = AutoHashMap([]const u8, ArrayList([]const u8)).init(allocator),
            .circular_deps = ArrayList(SemanticErrorInfo).init(allocator),
        };
    }
    
    pub fn deinit(self: *DependencyResolver) void {
        var iter = self.dependencies.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.dependencies.deinit();
        self.circular_deps.deinit();
    }
    
    pub fn addDependency(self: *DependencyResolver, from: []const u8, to: []const u8) !void {
        const result = try self.dependencies.getOrPut(from);
        if (!result.found_existing) {
            result.value_ptr.* = ArrayList([]const u8).init(self.allocator);
        }
        try result.value_ptr.append(to);
    }
    
    pub fn checkCircularDependencies(self: *DependencyResolver) ![]const SemanticErrorInfo {
        var visited = AutoHashMap([]const u8, bool).init(self.allocator);
        defer visited.deinit();
        
        var recursion_stack = AutoHashMap([]const u8, bool).init(self.allocator);
        defer recursion_stack.deinit();
        
        var func_iter = self.dependencies.iterator();
        while (func_iter.next()) |entry| {
            const func_name = entry.key_ptr.*;
            if (!visited.contains(func_name)) {
                try self.detectCycle(func_name, &visited, &recursion_stack);
            }
        }
        
        return self.circular_deps.toOwnedSlice();
    }
    
    fn detectCycle(self: *DependencyResolver, func_name: []const u8, visited: *AutoHashMap([]const u8, bool), recursion_stack: *AutoHashMap([]const u8, bool)) !void {
        try visited.put(func_name, true);
        try recursion_stack.put(func_name, true);
        
        if (self.dependencies.get(func_name)) |deps| {
            for (deps.items) |dep| {
                if (!visited.contains(dep)) {
                    try self.detectCycle(dep, visited, recursion_stack);
                } else if (recursion_stack.contains(dep)) {
                    try self.circular_deps.append(SemanticErrorInfo{
                        .error_type = SemanticError.RecursionDepthExceeded,
                        .message = "Circular dependency detected",
                        .position = .{ .line = 0, .column = 0 },
                        .severity = .warning,
                        .help_text = "Consider refactoring to break circular dependency",
                    });
                }
            }
        }
        
        _ = recursion_stack.remove(func_name);
    }
};

pub const AdvancedSemanticAnalyzer = struct {
    allocator: Allocator,
    null_safety: NullSafetyAnalyzer,
    bounds_checker: ArrayBoundsChecker,
    memory_analyzer: MemoryLifecycleAnalyzer,
    dependency_resolver: DependencyResolver,
    
    pub fn init(allocator: Allocator, null_safety_level: NullSafetyLevel) AdvancedSemanticAnalyzer {
        return AdvancedSemanticAnalyzer{
            .allocator = allocator,
            .null_safety = NullSafetyAnalyzer.init(allocator, null_safety_level),
            .bounds_checker = ArrayBoundsChecker.init(allocator),
            .memory_analyzer = MemoryLifecycleAnalyzer.init(allocator),
            .dependency_resolver = DependencyResolver.init(allocator),
        };
    }
    
    pub fn deinit(self: *AdvancedSemanticAnalyzer) void {
        self.null_safety.deinit();
        self.bounds_checker.deinit();
        self.memory_analyzer.deinit();
        self.dependency_resolver.deinit();
    }
    
    pub fn analyze(self: *AdvancedSemanticAnalyzer, program: *ast.Program, symbol_table: *SymbolTable) ![]const SemanticErrorInfo {
        var all_errors = ArrayList(SemanticErrorInfo).init(self.allocator);
        defer all_errors.deinit();
        
        for (program.functions) |*func| {
            try self.analyzeFunction(func, symbol_table);
        }
        
        const circular_deps = try self.dependency_resolver.checkCircularDependencies();
        try all_errors.appendSlice(circular_deps);
        self.allocator.free(circular_deps);
        
        try all_errors.appendSlice(self.null_safety.warnings.items);
        try all_errors.appendSlice(self.bounds_checker.warnings.items);
        try all_errors.appendSlice(self.memory_analyzer.warnings.items);
        
        try self.memory_analyzer.generateOptimizationHints();
        try all_errors.appendSlice(self.memory_analyzer.optimization_hints.items);
        
        return all_errors.toOwnedSlice();
    }
    
    fn analyzeFunction(self: *AdvancedSemanticAnalyzer, func: *ast.FunctionDeclaration, symbol_table: *SymbolTable) !void {
        try self.analyzeStatement(func.body, symbol_table);
        
        if (func.return_type) |return_type| {
            if (return_type.kind != .void) {
                try self.memory_analyzer.analyzeReturn(null);
            }
        }
    }
    
    fn analyzeStatement(self: *AdvancedSemanticAnalyzer, stmt: *Statement, symbol_table: *SymbolTable) !void {
        try self.null_safety.analyzeStatement(stmt, symbol_table);
        
        switch (stmt.kind) {
            .variable_declaration => try self.memory_analyzer.analyzeVariableDeclaration(stmt.data.variable_declaration),
            .expression => try self.analyzeExpression(stmt.data.expression, symbol_table),
            .return_statement => try self.memory_analyzer.analyzeReturn(stmt.data.return_statement),
            .block => {
                for (stmt.data.block.statements) |block_stmt| {
                    try self.analyzeStatement(block_stmt, symbol_table);
                }
            },
            .if_statement => {
                try self.analyzeStatement(stmt.data.if_statement.then_stmt, symbol_table);
                if (stmt.data.if_statement.else_stmt) |else_stmt| {
                    try self.analyzeStatement(else_stmt, symbol_table);
                }
            },
            .while_statement => try self.analyzeStatement(stmt.data.while_statement.body, symbol_table),
            .for_statement => {
                if (stmt.data.for_statement.init) |init_stmt| {
                    try self.analyzeStatement(init_stmt, symbol_table);
                }
                try self.analyzeStatement(stmt.data.for_statement.body, symbol_table);
            },
            .switch_statement => {
                for (stmt.data.switch_statement.cases) |case| {
                    for (case.statements) |case_stmt| {
                        try self.analyzeStatement(case_stmt, symbol_table);
                    }
                }
            },
        }
    }
    
    fn analyzeExpression(self: *AdvancedSemanticAnalyzer, expr: *Expression, symbol_table: *SymbolTable) !void {
        try self.null_safety.analyzeExpression(expr, symbol_table);
        
        switch (expr.kind) {
            .array_access => {
                _ = try self.bounds_checker.analyzeArrayAccess(expr.data.array_access, expr.position);
            },
            .assignment => try self.memory_analyzer.analyzeAssignment(expr.data.assignment),
            .call => {
                if (expr.data.call.callee.kind == .identifier) {
                    const func_name = expr.data.call.callee.data.identifier;
                    try self.dependency_resolver.addDependency("current", func_name);
                }
            },
            .array_literal => {
                const size = self.bounds_checker.analyzeArrayLiteral(expr.data.array_literal);
                _ = size;
            },
            .binary => {
                try self.analyzeExpression(expr.data.binary.left, symbol_table);
                try self.analyzeExpression(expr.data.binary.right, symbol_table);
            },
            .unary => try self.analyzeExpression(expr.data.unary.operand, symbol_table),
            .member_access => try self.analyzeExpression(expr.data.member_access.object, symbol_table),
            else => {},
        }
    }
};