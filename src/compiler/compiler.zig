const std = @import("std");
const managed_memory_mod = @import("../state/managed_memory.zig");
const chunk_mod = @import("chunk.zig");
const expression_mod = @import("../parser/parsed_expression.zig");
const stack_mod = @import("../state/stack.zig");
const value_mod = @import("../state/value.zig");

const mem = std.mem;
const Allocator = mem.Allocator;
const ManagedMemory = managed_memory_mod.ManagedMemory;
const Chunk = chunk_mod.Chunk;
const OpCode = chunk_mod.OpCode;
const ParsedExpression = expression_mod.ParsedExpression;
const Stack = stack_mod.Stack;
const Value = value_mod.Value;

const CompilerError = error{
    OutOfMemory,
    TooManyConstants,
};

pub const Compiler = struct {
    const Self = @This();

    allocator: Allocator,
    chunk: Chunk,

    pub fn compile(memory: *ManagedMemory, expression: *ParsedExpression) CompilerError!void {
        const allocator = memory.allocator();

        var compiler = Self{
            .allocator = allocator,
            .chunk = try Chunk.init(memory),
        };

        try compiler.compileExpression(expression);
        try compiler.chunk.writeByte(.return_, null);

        memory.vm_state = .{
            .chunk = compiler.chunk,
            .ip = @ptrCast(&compiler.chunk.code.items[0]),
            .stack = try Stack.init(allocator),
        };
    }

    fn compileExpression(self: *Self, expression: *ParsedExpression) CompilerError!void {
        switch (expression.*) {
            .literal => |literal| {
                const lexeme = literal.token.lexeme;
                const value: Value = switch (literal.kind) {
                    .int => .{
                        .int = std.fmt.parseInt(i64, lexeme, 10) catch unreachable,
                    },
                    .float => .{
                        .float = std.fmt.parseFloat(f64, lexeme) catch unreachable,
                    },
                    .bool => .{ .bool = lexeme.len == 4 },
                };

                try self.chunk.writeConstant(value, literal.token.position);
            },
            .binary => |binary| {
                try self.compileExpression(binary.left);
                try self.compileExpression(binary.right);
                try self.chunk.writeByte(switch (binary.operator_kind) {
                    .subtract => OpCode.subtract_int,
                    .add => OpCode.add_int,
                    .divide => OpCode.divide_int,
                    .multiply => OpCode.multiply_int,
                }, binary.operator_token.position);
            },
            .unary => |unary| {
                try self.compileExpression(unary.right);
                try self.chunk.writeByte(
                    if (unary.operator_kind == .negate) OpCode.negate_int else OpCode.invert,
                    unary.operator_token.position,
                );
            },
        }
    }
};
