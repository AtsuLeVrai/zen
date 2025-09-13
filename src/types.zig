const std = @import("std");

pub const Type = enum {
    void,
    i32,
    f64,
    bool,
    string,
    unknown,

    pub fn toString(self: Type) []const u8 {
        return switch (self) {
            .void => "void",
            .i32 => "i32",
            .f64 => "f64",
            .bool => "bool",
            .string => "string",
            .unknown => "unknown",
        };
    }

    pub fn fromString(str: []const u8) ?Type {
        if (std.mem.eql(u8, str, "void")) return .void;
        if (std.mem.eql(u8, str, "i32")) return .i32;
        if (std.mem.eql(u8, str, "f64")) return .f64;
        if (std.mem.eql(u8, str, "bool")) return .bool;
        if (std.mem.eql(u8, str, "string")) return .string;
        return null;
    }

    pub fn isNumeric(self: Type) bool {
        return self == .i32 or self == .f64;
    }

    pub fn canAssignTo(from: Type, to: Type) bool {
        if (from == to) return true;
        if (from == .unknown or to == .unknown) return true;

        // Allow i32 to f64 conversion
        if (from == .i32 and to == .f64) return true;

        return false;
    }

    pub fn getCommonType(type1: Type, type2: Type) Type {
        if (type1 == type2) return type1;
        if (type1 == .unknown) return type2;
        if (type2 == .unknown) return type1;

        // Numeric promotion: i32 + f64 = f64
        if ((type1 == .i32 and type2 == .f64) or (type1 == .f64 and type2 == .i32)) {
            return .f64;
        }

        return .unknown;
    }
};

pub const TypeError = error{
    TypeMismatch,
    UndefinedVariable,
    UndefinedFunction,
    InvalidOperation,
    InvalidAssignment,
    ArgumentCountMismatch,
    ReturnTypeMismatch,
    OutOfMemory,
};

// Type environment for tracking variable types
pub const TypeEnvironment = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    variables: std.StringHashMap(Type),
    functions: std.StringHashMap(FunctionType),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .variables = std.StringHashMap(Type).init(allocator),
            .functions = std.StringHashMap(FunctionType).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.variables.deinit();
        self.functions.deinit();
    }

    pub fn defineVariable(self: *Self, name: []const u8, var_type: Type) !void {
        try self.variables.put(name, var_type);
    }

    pub fn lookupVariable(self: *Self, name: []const u8) ?Type {
        return self.variables.get(name);
    }

    pub fn defineFunction(self: *Self, name: []const u8, func_type: FunctionType) !void {
        try self.functions.put(name, func_type);
    }

    pub fn lookupFunction(self: *Self, name: []const u8) ?FunctionType {
        return self.functions.get(name);
    }
};

pub const FunctionType = struct {
    parameters: []Type,
    return_type: Type,
};

// Built-in function types
pub fn getBuiltinFunctions(allocator: std.mem.Allocator) !std.StringHashMap(FunctionType) {
    var builtins = std.StringHashMap(FunctionType).init(allocator);

    // print(string) -> void
    const print_params = try allocator.dupe(Type, &[_]Type{.string});
    try builtins.put("print", FunctionType{
        .parameters = print_params,
        .return_type = .void,
    });

    // print_int(i32) -> void
    const print_int_params = try allocator.dupe(Type, &[_]Type{.i32});
    try builtins.put("print_int", FunctionType{
        .parameters = print_int_params,
        .return_type = .void,
    });

    return builtins;
}

pub fn deinitBuiltinFunctions(allocator: std.mem.Allocator, builtins: *std.StringHashMap(FunctionType)) void {
    var iterator = builtins.iterator();
    while (iterator.next()) |entry| {
        allocator.free(entry.value_ptr.parameters);
    }
    builtins.deinit();
}
