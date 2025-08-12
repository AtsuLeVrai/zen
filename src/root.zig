//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
const std = @import("std");
const testing = std.testing;

pub const lexer = @import("lexer.zig");
pub const unicode = @import("unicode.zig");
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const semantic = @import("semantic.zig");
pub const advanced_analysis = @import("advanced_analysis.zig");

// Re-export key types for convenience
pub const SemanticAnalyzer = semantic.SemanticAnalyzer;
pub const SymbolTable = semantic.SymbolTable;
pub const TypeChecker = semantic.TypeChecker;
pub const SemanticError = semantic.SemanticError;
pub const SemanticErrorInfo = semantic.SemanticErrorInfo;
pub const AdvancedSemanticAnalyzer = advanced_analysis.AdvancedSemanticAnalyzer;
pub const NullSafetyLevel = advanced_analysis.NullSafetyLevel;

test {
    _ = @import("semantic_test.zig");
}
