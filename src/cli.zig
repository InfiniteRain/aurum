const std = @import("std");
const clap = @import("clap");
const io_handler_mod = @import("io_handler.zig");
const tokenizer_mod = @import("parser/tokenizer.zig");
const parser_mod = @import("parser/parser.zig");
const sema_mod = @import("sema/sema.zig");
const managed_memory_mod = @import("state/managed_memory.zig");
const compiler_mod = @import("compiler/compiler.zig");
const vm_mod = @import("vm/vm.zig");

const Allocator = std.mem.Allocator;
const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const IoHandler = io_handler_mod.IoHandler;
const Tokenizer = tokenizer_mod.Tokenizer;
const Parser = parser_mod.Parser;
const Sema = sema_mod.Sema;
const ManagedMemory = managed_memory_mod.ManagedMemory;
const Compiler = compiler_mod.Compiler;
const Vm = vm_mod.Vm;

pub fn runCli() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer().any();
    const stderr = std.io.getStdErr().writer().any();
    const stdin = std.io.getStdIn().reader().any();

    var io = try IoHandler.init(allocator, &stdin, &stdout, &stderr);
    defer io.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help         Display help and exit.
        \\--dprint-byte-code Print compiled bytecode.
        \\--dtrace-execution Trace code execution.
        \\<file>             Script file to execute.
        \\
    );

    const parsers = comptime .{
        .file = clap.parsers.string,
    };

    var diag = clap.Diagnostic{};
    const res = clap.parse(clap.Help, &params, parsers, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(stderr, err) catch {};
        try usage(&io, &params);
        std.posix.exit(64);
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try usage(&io, &params);
        io.out("\n\n");
        try options(&io, &params);
        return;
    }

    if (res.positionals.len == 0) {
        try usage(&io, &params);
        io.out("\n");
        return;
    }

    try runFile(allocator, &io, res.positionals[0], res.args);
}

fn runFile(allocator: Allocator, io: *IoHandler, file_path: []const u8, args: anytype) !void {
    const source = try readFileAlloc(allocator, file_path, io);

    var tokenizer = Tokenizer.init(source);

    var parser = Parser.init(allocator);
    var parser_diags = Parser.Diagnostics.init(allocator);
    defer parser_diags.deinit();

    const parsed_stmt = parser.parse(&tokenizer, &parser_diags) catch |err| switch (err) {
        error.ParseFailure => {
            for (parser_diags.getEntries()) |diag| {
                io.outf("Error at {}:{}: {s}\n", .{
                    diag.token.position.line,
                    diag.token.position.column,
                    diag.message,
                });
            }
            std.posix.exit(65);
        },
        else => return err,
    };
    defer parsed_stmt.destroy(allocator);

    var sema = Sema.init(allocator);
    var sema_diags = Sema.Diagnostics.init(allocator);
    defer sema_diags.deinit();

    var sema_stmt = sema.analyze(parsed_stmt, &sema_diags) catch |err| switch (err) {
        error.SemaFailure => {
            for (sema_diags.getEntries()) |diag| {
                io.outf("Error at {}:{}: {s}\n", .{
                    diag.position.line,
                    diag.position.column,
                    diag.message,
                });
            }
            std.posix.exit(65);
        },
        else => return err,
    };
    defer sema_stmt.destroy(allocator);

    var memory = ManagedMemory.init(allocator);
    defer memory.deinit();

    try Compiler.compile(&memory, sema_stmt);

    if (args.@"dprint-byte-code" > 0) {
        io.out("== CHUNK ==\n");
        memory.vm_state.?.chunk.print(io);
        io.out("\n== EXECUTION ==\n");
    }

    var vm_diagnostics = Vm.Diagnostics.init(allocator);
    defer vm_diagnostics.deinit();

    Vm.interpret(&memory, io, &vm_diagnostics, .{
        .trace_execution = args.@"dtrace-execution" > 0,
    }) catch |err| switch (err) {
        error.Panic => {
            const diags = vm_diagnostics.getEntries();

            io.outf("Panic at {}:{}: {s}\n", .{
                diags[0].position.line,
                diags[0].position.column,
                diags[0].message,
            });
        },
        else => return err,
    };
}

fn readFileAlloc(allocator: Allocator, file_path: []const u8, io: *IoHandler) ![]u8 {
    const file = std.fs.cwd().openFile(file_path, .{ .mode = .read_only }) catch {
        io.outf("Could not open file '{s}'.\n", .{file_path});
        std.posix.exit(74);
    };
    defer file.close();

    try file.seekFromEnd(0);
    const end = try file.getPos();
    try file.seekTo(0);

    return file.reader().readAllAlloc(allocator, end) catch {
        io.outf("Not enough memory to read '{s}'.\n", .{file_path});
        std.posix.exit(74);
    };
}

fn usage(io: *IoHandler, params: anytype) !void {
    io.out("Usage: ");
    try clap.usage(io.stderr.*, clap.Help, params);
}

fn options(io: *IoHandler, params: anytype) !void {
    io.out("Options:\n");
    try clap.help(io.stderr.*, clap.Help, params, .{});
}
