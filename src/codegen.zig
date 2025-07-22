const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const ast = @import("ast.zig");
const errors = @import("errors.zig");
const main = @import("main.zig");

const AST = ast.AST;
const Node = ast.Node;
const NodeId = ast.NodeId;
const ZenError = errors.ZenError;

pub const CodeGen = struct {
    allocator: Allocator,
    target: Target,
    output: ArrayList(u8),
    indent_level: u32,
    
    pub const Target = enum {
        native,
        wasm,
        hybrid,
    };
    
    pub fn init(allocator: Allocator, target: Target) CodeGen {
        return CodeGen{
            .allocator = allocator,
            .target = target,
            .output = ArrayList(u8).init(allocator),
            .indent_level = 0,
        };
    }
    
    pub fn deinit(self: *CodeGen) void {
        self.output.deinit();
    }
    
    pub fn generate(self: *CodeGen, ast_instance: *AST) ZenError![]u8 {
        try self.generateNode(ast_instance, ast_instance.root);
        return self.output.toOwnedSlice();
    }
    
    fn generateNode(self: *CodeGen, ast_instance: *AST, node_id: NodeId) ZenError!void {
        const node = ast_instance.getNode(node_id) orelse return ZenError.CodegenError;
        
        switch (node.data) {
            .program => |program| {
                try self.generateProgram(ast_instance, program);
            },
            .function_decl => |func| {
                try self.generateFunction(ast_instance, func);
            },
            .variable_decl => |var_decl| {
                try self.generateVariableDeclaration(ast_instance, var_decl);
            },
            .type_decl => |type_decl| {
                try self.generateTypeDeclaration(ast_instance, type_decl);
            },
            .import_decl => |import_decl| {
                try self.generateImportDeclaration(ast_instance, import_decl);
            },
            .export_decl => |export_decl| {
                try self.generateExportDeclaration(ast_instance, export_decl);
            },
            .return_stmt => |return_stmt| {
                try self.generateReturnStatement(ast_instance, return_stmt);
            },
            .if_stmt => |if_stmt| {
                try self.generateIfStatement(ast_instance, if_stmt);
            },
            .while_stmt => |while_stmt| {
                try self.generateWhileStatement(ast_instance, while_stmt);
            },
            .for_stmt => |for_stmt| {
                try self.generateForStatement(ast_instance, for_stmt);
            },
            .expression_stmt => |expr_stmt| {
                try self.generateNode(ast_instance, expr_stmt.expression);
                try self.writeLine(";");
            },
            .block_stmt => |block| {
                try self.generateBlockStatement(ast_instance, block);
            },
            .binary_expr => |binary| {
                try self.generateBinaryExpression(ast_instance, binary);
            },
            .unary_expr => |unary| {
                try self.generateUnaryExpression(ast_instance, unary);
            },
            .call_expr => |call| {
                try self.generateCallExpression(ast_instance, call);
            },
            .member_expr => |member| {
                try self.generateMemberExpression(ast_instance, member);
            },
            .index_expr => |index| {
                try self.generateIndexExpression(ast_instance, index);
            },
            .literal_expr => |literal| {
                try self.generateLiteral(literal);
            },
            .identifier_expr => |ident| {
                try self.write(ident.name);
            },
            .array_expr => |array| {
                try self.generateArrayExpression(ast_instance, array);
            },
            else => {
                try self.write("/* Unimplemented node type */");
            },
        }
    }
    
    fn generateProgram(self: *CodeGen, ast_instance: *AST, program: ast.Program) ZenError!void {
        // Generate target-specific headers
        switch (self.target) {
            .native => {
                try self.writeLine("#include <stdio.h>");
                try self.writeLine("#include <stdlib.h>");
                try self.writeLine("#include <stdint.h>");
                try self.writeLine("#include <stdbool.h>");
                try self.writeLine("");
            },
            .wasm => {
                try self.writeLine("// WebAssembly target");
                try self.writeLine("export { main };");
                try self.writeLine("");
            },
            .hybrid => {
                try self.writeLine("#ifdef __EMSCRIPTEN__");
                try self.writeLine("// WebAssembly mode");
                try self.writeLine("#else");
                try self.writeLine("// Native mode");
                try self.writeLine("#include <stdio.h>");
                try self.writeLine("#include <stdlib.h>");
                try self.writeLine("#include <stdint.h>");
                try self.writeLine("#include <stdbool.h>");
                try self.writeLine("#endif");
                try self.writeLine("");
            },
        }
        
        // Generate all declarations
        for (program.declarations) |decl_id| {
            try self.generateNode(ast_instance, decl_id);
            try self.writeLine("");
        }
        
        // Add runtime helpers
        try self.generateRuntimeHelpers();
    }
    
    fn generateFunction(self: *CodeGen, ast_instance: *AST, func: ast.FunctionDecl) ZenError!void {
        // Function signature
        const return_type_str = try self.typeToString(func.return_type);
        defer if (func.return_type) |_| self.allocator.free(return_type_str);
        
        try self.writeIndent();
        
        // Handle annotations
        for (func.annotations) |annotation| {
            if (std.mem.eql(u8, annotation.name, "@target")) {
                // Generate conditional compilation for target-specific functions
                try self.write("#ifdef TARGET_");
                // This is simplified - would need proper annotation parsing
                try self.writeLine("NATIVE");
            }
        }
        
        if (func.is_async) {
            try self.write("async ");
        }
        
        try self.write(return_type_str);
        try self.write(" ");
        try self.write(func.name);
        try self.write("(");
        
        // Parameters
        for (func.params, 0..) |param, i| {
            if (i > 0) try self.write(", ");
            const param_type_str = try self.typeToString(param.param_type);
            defer self.allocator.free(param_type_str);
            
            try self.write(param_type_str);
            try self.write(" ");
            try self.write(param.name);
        }
        
        try self.write(")");
        
        // Function body
        if (self.target == .wasm and std.mem.eql(u8, func.name, "main")) {
            try self.writeLine(" {");
        } else {
            try self.writeLine(" {");
        }
        
        self.indent_level += 1;
        try self.generateNode(ast_instance, func.body);
        self.indent_level -= 1;
        
        try self.writeLine("}");
        
        // Close conditional compilation if needed
        for (func.annotations) |annotation| {
            if (std.mem.eql(u8, annotation.name, "@target")) {
                try self.writeLine("#endif");
            }
        }
    }
    
    fn generateVariableDeclaration(self: *CodeGen, ast_instance: *AST, var_decl: ast.VariableDecl) ZenError!void {
        try self.writeIndent();
        
        const type_str = if (var_decl.var_type) |var_type| 
            try self.typeToString(var_type)
        else 
            try self.allocator.dupe(u8, "auto"); // C++ style auto, would need type inference
            
        defer self.allocator.free(type_str);
        
        if (var_decl.is_const) {
            try self.write("const ");
        }
        
        try self.write(type_str);
        try self.write(" ");
        try self.write(var_decl.name);
        
        if (var_decl.initializer) |init_id| {
            try self.write(" = ");
            try self.generateNode(ast_instance, init_id);
        }
        
        try self.writeLine(";");
    }
    
    fn generateTypeDeclaration(self: *CodeGen, ast_instance: *AST, type_decl: ast.TypeDecl) ZenError!void {
        _ = ast_instance;
        
        try self.writeIndent();
        try self.write("typedef struct {");
        try self.writeLine("");
        
        self.indent_level += 1;
        for (type_decl.fields) |field| {
            try self.writeIndent();
            const field_type_str = try self.typeToString(field.field_type);
            defer self.allocator.free(field_type_str);
            
            try self.write(field_type_str);
            try self.write(" ");
            try self.write(field.name);
            try self.writeLine(";");
        }
        self.indent_level -= 1;
        
        try self.write("} ");
        try self.write(type_decl.name);
        try self.writeLine(";");
    }
    
    fn generateImportDeclaration(self: *CodeGen, ast_instance: *AST, import_decl: ast.ImportDecl) ZenError!void {
        _ = ast_instance;
        
        switch (self.target) {
            .native => {
                try self.write("#include ");
                try self.writeLine(import_decl.path);
            },
            .wasm => {
                try self.write("import { ");
                for (import_decl.items, 0..) |item, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(item.name);
                }
                try self.write(" } from ");
                try self.write(import_decl.path);
                try self.writeLine(";");
            },
            .hybrid => {
                try self.writeLine("#ifdef __EMSCRIPTEN__");
                try self.write("import { ");
                for (import_decl.items, 0..) |item, i| {
                    if (i > 0) try self.write(", ");
                    try self.write(item.name);
                }
                try self.write(" } from ");
                try self.write(import_decl.path);
                try self.writeLine(";");
                try self.writeLine("#else");
                try self.write("#include ");
                try self.writeLine(import_decl.path);
                try self.writeLine("#endif");
            },
        }
    }
    
    fn generateExportDeclaration(self: *CodeGen, ast_instance: *AST, export_decl: ast.ExportDecl) ZenError!void {
        switch (self.target) {
            .wasm => try self.write("export "),
            else => {},
        }
        
        try self.generateNode(ast_instance, export_decl.declaration);
    }
    
    fn generateReturnStatement(self: *CodeGen, ast_instance: *AST, return_stmt: ast.ReturnStmt) ZenError!void {
        try self.writeIndent();
        try self.write("return");
        
        if (return_stmt.value) |value_id| {
            try self.write(" ");
            try self.generateNode(ast_instance, value_id);
        }
        
        try self.writeLine(";");
    }
    
    fn generateIfStatement(self: *CodeGen, ast_instance: *AST, if_stmt: ast.IfStmt) ZenError!void {
        try self.writeIndent();
        try self.write("if (");
        try self.generateNode(ast_instance, if_stmt.condition);
        try self.writeLine(") {");
        
        self.indent_level += 1;
        try self.generateNode(ast_instance, if_stmt.then_stmt);
        self.indent_level -= 1;
        
        try self.writeIndent();
        try self.write("}");
        
        if (if_stmt.else_stmt) |else_id| {
            try self.writeLine(" else {");
            self.indent_level += 1;
            try self.generateNode(ast_instance, else_id);
            self.indent_level -= 1;
            try self.writeIndent();
            try self.write("}");
        }
        
        try self.writeLine("");
    }
    
    fn generateWhileStatement(self: *CodeGen, ast_instance: *AST, while_stmt: ast.WhileStmt) ZenError!void {
        try self.writeIndent();
        try self.write("while (");
        try self.generateNode(ast_instance, while_stmt.condition);
        try self.writeLine(") {");
        
        self.indent_level += 1;
        try self.generateNode(ast_instance, while_stmt.body);
        self.indent_level -= 1;
        
        try self.writeIndent();
        try self.writeLine("}");
    }
    
    fn generateForStatement(self: *CodeGen, ast_instance: *AST, for_stmt: ast.ForStmt) ZenError!void {
        // This is simplified - would need proper iteration logic
        try self.writeIndent();
        try self.write("for (auto ");
        try self.write(for_stmt.variable);
        try self.write(" : ");
        try self.generateNode(ast_instance, for_stmt.iterable);
        try self.writeLine(") {");
        
        self.indent_level += 1;
        try self.generateNode(ast_instance, for_stmt.body);
        self.indent_level -= 1;
        
        try self.writeIndent();
        try self.writeLine("}");
    }
    
    fn generateBlockStatement(self: *CodeGen, ast_instance: *AST, block: ast.BlockStmt) ZenError!void {
        for (block.statements) |stmt_id| {
            try self.generateNode(ast_instance, stmt_id);
        }
    }
    
    fn generateBinaryExpression(self: *CodeGen, ast_instance: *AST, binary: ast.BinaryExpr) ZenError!void {
        const needs_parens = true; // Simplified - would need precedence analysis
        
        if (needs_parens) try self.write("(");
        
        try self.generateNode(ast_instance, binary.left);
        
        const op_str = switch (binary.operator) {
            .add => " + ",
            .subtract => " - ",
            .multiply => " * ",
            .divide => " / ",
            .modulo => " % ",
            .equal => " == ",
            .not_equal => " != ",
            .less_than => " < ",
            .less_equal => " <= ",
            .greater_than => " > ",
            .greater_equal => " >= ",
            .and_op => " && ",
            .or_op => " || ",
            .assign => " = ",
            .add_assign => " += ",
            .subtract_assign => " -= ",
            .multiply_assign => " *= ",
            .divide_assign => " /= ",
            .in_op => " in ", // Would need special handling
            .is_op => " == ", // Simplified
        };
        
        try self.write(op_str);
        try self.generateNode(ast_instance, binary.right);
        
        if (needs_parens) try self.write(")");
    }
    
    fn generateUnaryExpression(self: *CodeGen, ast_instance: *AST, unary: ast.UnaryExpr) ZenError!void {
        const op_str = switch (unary.operator) {
            .minus => "-",
            .not_op => "!",
            .question => "", // Error propagation would need special handling
        };
        
        try self.write(op_str);
        try self.generateNode(ast_instance, unary.operand);
    }
    
    fn generateCallExpression(self: *CodeGen, ast_instance: *AST, call: ast.CallExpr) ZenError!void {
        try self.generateNode(ast_instance, call.callee);
        try self.write("(");
        
        for (call.arguments, 0..) |arg_id, i| {
            if (i > 0) try self.write(", ");
            try self.generateNode(ast_instance, arg_id);
        }
        
        try self.write(")");
    }
    
    fn generateMemberExpression(self: *CodeGen, ast_instance: *AST, member: ast.MemberExpr) ZenError!void {
        try self.generateNode(ast_instance, member.object);
        try self.write(".");
        try self.write(member.property);
    }
    
    fn generateIndexExpression(self: *CodeGen, ast_instance: *AST, index: ast.IndexExpr) ZenError!void {
        try self.generateNode(ast_instance, index.object);
        try self.write("[");
        try self.generateNode(ast_instance, index.index);
        try self.write("]");
    }
    
    fn generateArrayExpression(self: *CodeGen, ast_instance: *AST, array: ast.ArrayExpr) ZenError!void {
        try self.write("{");
        
        for (array.elements, 0..) |elem_id, i| {
            if (i > 0) try self.write(", ");
            try self.generateNode(ast_instance, elem_id);
        }
        
        try self.write("}");
    }
    
    fn generateLiteral(self: *CodeGen, literal: ast.LiteralExpr) ZenError!void {
        switch (literal.value) {
            .integer => |val| {
                const str = try std.fmt.allocPrint(self.allocator, "{d}", .{val});
                defer self.allocator.free(str);
                try self.write(str);
            },
            .float => |val| {
                const str = try std.fmt.allocPrint(self.allocator, "{d}", .{val});
                defer self.allocator.free(str);
                try self.write(str);
            },
            .string => |val| {
                try self.write("\"");
                try self.write(val[1..val.len-1]); // Remove quotes
                try self.write("\"");
            },
            .boolean => |val| {
                try self.write(if (val) "true" else "false");
            },
            .null_value => {
                try self.write("NULL");
            },
        }
    }
    
    fn generateRuntimeHelpers(self: *CodeGen) ZenError!void {
        try self.writeLine("// Runtime helpers");
        
        // Print function for different targets
        switch (self.target) {
            .native => {
                try self.writeLine("void zen_print(const char* str) {");
                try self.writeLine("    printf(\"%s\\n\", str);");
                try self.writeLine("}");
            },
            .wasm => {
                try self.writeLine("function zen_print(str) {");
                try self.writeLine("    console.log(str);");
                try self.writeLine("}");
            },
            .hybrid => {
                try self.writeLine("#ifdef __EMSCRIPTEN__");
                try self.writeLine("function zen_print(str) {");
                try self.writeLine("    console.log(str);");
                try self.writeLine("}");
                try self.writeLine("#else");
                try self.writeLine("void zen_print(const char* str) {");
                try self.writeLine("    printf(\"%s\\n\", str);");
                try self.writeLine("}");
                try self.writeLine("#endif");
            },
        }
        
        try self.writeLine("");
    }
    
    fn typeToString(self: *CodeGen, zen_type: ?ast.ZenType) ![]u8 {
        if (zen_type == null) {
            return try self.allocator.dupe(u8, "void");
        }
        
        return switch (zen_type.?) {
            .primitive => |prim| switch (prim) {
                .i32 => try self.allocator.dupe(u8, "int32_t"),
                .i64 => try self.allocator.dupe(u8, "int64_t"),
                .f32 => try self.allocator.dupe(u8, "float"),
                .f64 => try self.allocator.dupe(u8, "double"),
                .string => switch (self.target) {
                    .native => try self.allocator.dupe(u8, "const char*"),
                    .wasm => try self.allocator.dupe(u8, "string"),
                    .hybrid => try self.allocator.dupe(u8, "const char*"),
                },
                .bool => try self.allocator.dupe(u8, "bool"),
                .void => try self.allocator.dupe(u8, "void"),
            },
            .optional => |inner| {
                const inner_str = try self.typeToString(inner.*);
                defer self.allocator.free(inner_str);
                return try std.fmt.allocPrint(self.allocator, "{s}*", .{inner_str}); // Simplified nullable
            },
            .array => |inner| {
                const inner_str = try self.typeToString(inner.*);
                defer self.allocator.free(inner_str);
                return try std.fmt.allocPrint(self.allocator, "{s}[]", .{inner_str}); // Simplified array
            },
            .custom => |name| try self.allocator.dupe(u8, name),
            .function => |func_type| {
                _ = func_type; // TODO: Implement function type strings
                return try self.allocator.dupe(u8, "void*");
            },
            .result => |result_type| {
                _ = result_type; // TODO: Implement Result<T, E> type
                return try self.allocator.dupe(u8, "int"); // Simplified
            },
        };
    }
    
    fn write(self: *CodeGen, str: []const u8) !void {
        try self.output.appendSlice(str);
    }
    
    fn writeLine(self: *CodeGen, str: []const u8) !void {
        try self.write(str);
        try self.write("\n");
    }
    
    fn writeIndent(self: *CodeGen) !void {
        for (0..self.indent_level) |_| {
            try self.write("    "); // 4 spaces per indent level
        }
    }
};

test "codegen basic function" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var ast_instance = ast.AST.init(allocator);
    defer ast_instance.deinit();
    
    var codegen = CodeGen.init(allocator, .native);
    defer codegen.deinit();
    
    // This is a placeholder test - in reality we'd create a proper AST
    try testing.expect(true);
}