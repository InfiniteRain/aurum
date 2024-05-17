const std = @import("std");
const io_handler = @import("io_handler.zig");
const tokenizer_mod = @import("tokenizer.zig");
const parser_mod = @import("parser.zig");
const managed_memory_mod = @import("managed_memory.zig");
const compiler_mod = @import("compiler.zig");
const chunk_mod = @import("chunk.zig");

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const IoHandler = io_handler.IoHandler;
const Tokenizer = tokenizer_mod.Tokenizer;
const Parser = parser_mod.Parser;
const ManagedMemory = managed_memory_mod.ManagedMemory;
const Compiler = compiler_mod.Compiler;
const OpCode = chunk_mod.OpCode;

pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();
    var stdin = std.io.getStdIn().reader();

    var io = try IoHandler.init(allocator, &stdin, &stdout, &stderr);
    defer io.deinit();

    const source = "(5 + \n10) * \n30";
    var tokenizer = Tokenizer.init(source);

    var parser = Parser.init(&tokenizer);
    const expr = parser.parse(allocator) catch |err| switch (err) {
        error.ParseFailure => {
            io.outf("{s}\n", .{parser.err.?.message});
            return;
        },
        else => return err,
    };
    defer expr.destroy(allocator);

    var memory = ManagedMemory.init(allocator);
    defer memory.deinit();

    try Compiler.compile(&memory, expr);

    memory.compiled_state.?.root_chunk.print(&io);
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
