const std = @import("std");
const io_handler = @import("io_handler.zig");

const GeneralPurposeAllocator = std.heap.GeneralPurposeAllocator;
const IoHandler = io_handler.IoHandler;

pub fn main() !void {
    var gpa = GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var stdout = std.io.getStdOut().writer();
    var stderr = std.io.getStdErr().writer();
    var stdin = std.io.getStdIn().reader();

    var io = try IoHandler.init(allocator, &stdin, &stdout, &stderr);
    defer io.deinit();

    io.out("Hello, world!!");
}