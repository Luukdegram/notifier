const std = @import("std");
const Inotify = @import("inotify.zig");

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // open the current directory to watch
    var cwd = try std.process.getCwdAlloc(&gpa.allocator);
    defer gpa.allocator.free(cwd);

    var instance = try Inotify.init(&gpa.allocator);
    defer instance.deinit();

    try instance.addWatcher("/home/luuk/projects/zoog", .{ .modify = true });

    try try instance.watch(print);
}

fn print(event: Inotify.Event, name: ?[]const u8) !void {
    std.debug.print("Event: {}\n", .{event});

    if (name) |n| std.debug.print("Name: {s} {d}\n", .{ n, n.len });
}
