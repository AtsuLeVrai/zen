const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const errors = @import("errors.zig");
const SourceSpan = errors.SourceSpan;

pub const NodeId = u32;

pub const ZenType = union(enum) {
    primitive: PrimitiveType,
    optional: *ZenType,
    array: *ZenType,
    custom: []const u8,
    function: FunctionType,
    result: ResultType,
    
    pub const PrimitiveType = enum {
        i32,
        i64,
        f32,
        f64,
        string,
        bool,
        void,
    };
    
    pub const FunctionType = struct {
        params: []ZenType,
        return_type: *ZenType,
    };
    
    pub const ResultType = struct {
        ok_type: *ZenType,
        err_type: *ZenType,
    };
};

pub const Node = struct {
    id: NodeId,
    span: SourceSpan,
    data: NodeData,
    
    pub const NodeData = union(enum) {
        program: Program,
        function_decl: FunctionDecl,
        variable_decl: VariableDecl,
        type_decl: TypeDecl,
        import_decl: ImportDecl,
        export_decl: ExportDecl,
        
        // Statements
        expression_stmt: ExpressionStmt,
        return_stmt: ReturnStmt,
        if_stmt: IfStmt,
        while_stmt: WhileStmt,
        for_stmt: ForStmt,
        switch_stmt: SwitchStmt,
        throw_stmt: ThrowStmt,
        block_stmt: BlockStmt,
        
        // Expressions
        binary_expr: BinaryExpr,
        unary_expr: UnaryExpr,
        call_expr: CallExpr,
        member_expr: MemberExpr,
        index_expr: IndexExpr,
        assign_expr: AssignExpr,
        literal_expr: LiteralExpr,
        identifier_expr: IdentifierExpr,
        array_expr: ArrayExpr,
        interpolation_expr: InterpolationExpr,
        range_expr: RangeExpr,
        try_expr: TryExpr,
        catch_expr: CatchExpr,
        async_expr: AsyncExpr,
        await_expr: AwaitExpr,
        type_cast_expr: TypeCastExpr,
    };
};

pub const Program = struct {
    declarations: []NodeId,
};

pub const FunctionDecl = struct {
    name: []const u8,
    params: []Parameter,
    return_type: ?ZenType,
    body: NodeId,
    is_async: bool,
    annotations: []Annotation,
    
    pub const Parameter = struct {
        name: []const u8,
        param_type: ZenType,
        span: SourceSpan,
    };
};

pub const VariableDecl = struct {
    name: []const u8,
    var_type: ?ZenType,
    initializer: ?NodeId,
    is_const: bool,
};

pub const TypeDecl = struct {
    name: []const u8,
    fields: []Field,
    
    pub const Field = struct {
        name: []const u8,
        field_type: ZenType,
        span: SourceSpan,
    };
};

pub const ImportDecl = struct {
    path: []const u8,
    items: []ImportItem,
    
    pub const ImportItem = struct {
        name: []const u8,
        alias: ?[]const u8,
    };
};

pub const ExportDecl = struct {
    declaration: NodeId,
};

pub const ExpressionStmt = struct {
    expression: NodeId,
};

pub const ReturnStmt = struct {
    value: ?NodeId,
};

pub const IfStmt = struct {
    condition: NodeId,
    then_stmt: NodeId,
    else_stmt: ?NodeId,
};

pub const WhileStmt = struct {
    condition: NodeId,
    body: NodeId,
};

pub const ForStmt = struct {
    variable: []const u8,
    iterable: NodeId,
    body: NodeId,
};

pub const SwitchStmt = struct {
    expression: NodeId,
    cases: []SwitchCase,
    default_case: ?NodeId,
    
    pub const SwitchCase = struct {
        value: NodeId,
        body: NodeId,
    };
};

pub const ThrowStmt = struct {
    expression: NodeId,
};

pub const BlockStmt = struct {
    statements: []NodeId,
};

pub const BinaryExpr = struct {
    left: NodeId,
    operator: BinaryOperator,
    right: NodeId,
    
    pub const BinaryOperator = enum {
        // Arithmetic
        add,
        subtract,
        multiply,
        divide,
        modulo,
        
        // Comparison
        equal,
        not_equal,
        less_than,
        less_equal,
        greater_than,
        greater_equal,
        
        // Logical
        and_op,
        or_op,
        
        // Special
        in_op,      // for range checks: age in 18..65
        is_op,      // for identity: a is b
        assign,
        
        // Compound assignment
        add_assign,
        subtract_assign,
        multiply_assign,
        divide_assign,
    };
};

pub const UnaryExpr = struct {
    operator: UnaryOperator,
    operand: NodeId,
    
    pub const UnaryOperator = enum {
        minus,
        not_op,
        question,  // for error propagation: divide(10, 2)?
    };
};

pub const CallExpr = struct {
    callee: NodeId,
    arguments: []NodeId,
};

pub const MemberExpr = struct {
    object: NodeId,
    property: []const u8,
};

pub const IndexExpr = struct {
    object: NodeId,
    index: NodeId,
};

pub const AssignExpr = struct {
    target: NodeId,
    value: NodeId,
};

pub const LiteralExpr = struct {
    value: LiteralValue,
    
    pub const LiteralValue = union(enum) {
        integer: i64,
        float: f64,
        string: []const u8,
        boolean: bool,
        null_value,
    };
};

pub const IdentifierExpr = struct {
    name: []const u8,
};

pub const ArrayExpr = struct {
    elements: []NodeId,
};

pub const InterpolationExpr = struct {
    parts: []NodeId, // Mix of string literals and expressions
};

pub const RangeExpr = struct {
    start: NodeId,
    end: NodeId,
    inclusive: bool, // true for ..=, false for ..
};

pub const TryExpr = struct {
    expression: NodeId,
    default_value: NodeId, // for "try expr else default"
};

pub const CatchExpr = struct {
    expression: NodeId,
    handlers: []CatchHandler,
    
    pub const CatchHandler = struct {
        error_type: ?[]const u8,
        variable: ?[]const u8,
        body: NodeId,
    };
};

pub const AsyncExpr = struct {
    expression: NodeId,
};

pub const AwaitExpr = struct {
    expression: NodeId,
};

pub const TypeCastExpr = struct {
    expression: NodeId,
    target_type: ZenType,
};

pub const Annotation = struct {
    name: []const u8,
    arguments: []NodeId,
};

pub const AST = struct {
    allocator: Allocator,
    nodes: ArrayList(Node),
    root: NodeId,
    next_id: NodeId,
    
    pub fn init(allocator: Allocator) AST {
        return AST{
            .allocator = allocator,
            .nodes = ArrayList(Node).init(allocator),
            .root = 0,
            .next_id = 0,
        };
    }
    
    pub fn deinit(self: *AST) void {
        self.nodes.deinit();
    }
    
    pub fn addNode(self: *AST, span: SourceSpan, data: Node.NodeData) !NodeId {
        const id = self.next_id;
        self.next_id += 1;
        
        const node = Node{
            .id = id,
            .span = span,
            .data = data,
        };
        
        try self.nodes.append(node);
        return id;
    }
    
    pub fn getNode(self: *AST, id: NodeId) ?*Node {
        if (id >= self.nodes.items.len) return null;
        return &self.nodes.items[id];
    }
    
    pub fn setRoot(self: *AST, root: NodeId) void {
        self.root = root;
    }
};

// Helper functions for creating nodes
pub const NodeBuilder = struct {
    ast: *AST,
    
    pub fn init(ast: *AST) NodeBuilder {
        return NodeBuilder{ .ast = ast };
    }
    
    pub fn createProgram(self: *NodeBuilder, span: SourceSpan, declarations: []NodeId) !NodeId {
        const program = Program{ .declarations = declarations };
        return self.ast.addNode(span, .{ .program = program });
    }
    
    pub fn createFunction(
        self: *NodeBuilder,
        span: SourceSpan,
        name: []const u8,
        params: []FunctionDecl.Parameter,
        return_type: ?ZenType,
        body: NodeId,
        is_async: bool,
        annotations: []Annotation,
    ) !NodeId {
        const func = FunctionDecl{
            .name = name,
            .params = params,
            .return_type = return_type,
            .body = body,
            .is_async = is_async,
            .annotations = annotations,
        };
        return self.ast.addNode(span, .{ .function_decl = func });
    }
    
    pub fn createBinaryExpr(
        self: *NodeBuilder,
        span: SourceSpan,
        left: NodeId,
        operator: BinaryExpr.BinaryOperator,
        right: NodeId,
    ) !NodeId {
        const binary = BinaryExpr{
            .left = left,
            .operator = operator,
            .right = right,
        };
        return self.ast.addNode(span, .{ .binary_expr = binary });
    }
    
    pub fn createLiteral(self: *NodeBuilder, span: SourceSpan, value: LiteralExpr.LiteralValue) !NodeId {
        const literal = LiteralExpr{ .value = value };
        return self.ast.addNode(span, .{ .literal_expr = literal });
    }
    
    pub fn createIdentifier(self: *NodeBuilder, span: SourceSpan, name: []const u8) !NodeId {
        const ident = IdentifierExpr{ .name = name };
        return self.ast.addNode(span, .{ .identifier_expr = ident });
    }
    
    pub fn createBlock(self: *NodeBuilder, span: SourceSpan, statements: []NodeId) !NodeId {
        const block = BlockStmt{ .statements = statements };
        return self.ast.addNode(span, .{ .block_stmt = block });
    }
};

test "AST creation" {
    const testing = std.testing;
    const allocator = testing.allocator;
    
    var ast = AST.init(allocator);
    defer ast.deinit();
    
    var builder = NodeBuilder.init(&ast);
    
    const span = SourceSpan.init(
        errors.Position.init(0, 0, 0),
        errors.Position.init(0, 10, 10),
        "test.zen"
    );
    
    const literal_id = try builder.createLiteral(span, .{ .integer = 42 });
    const node = ast.getNode(literal_id);
    
    try testing.expect(node != null);
    try testing.expectEqual(@as(NodeId, 0), node.?.id);
}