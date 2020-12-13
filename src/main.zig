const std = @import("std");
const Inotify = @import("inotify.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // open the current directory to watch
    var cwd = try std.process.getCwdAlloc(&gpa.allocator);
    defer gpa.allocator.free(cwd);

    var instance = try Inotify.init(&gpa.allocator);
    defer instance.deinit();

    try instance.addWatcher(cwd, .{ .modify = true });
    var main_task = async runNotifier(&instance);

    try nosuspend await main_task;
}

pub fn runNotifier(instance: *Inotify) !void {
    var frame = async handleUpdates(instance);
    while (true) {
        instance.poll(-1);
    }

    try await frame;
}

pub fn handleUpdates(instance: *Inotify) !void {
    var name_buffer: [100]u8 = undefined;
    var event = try instance.get(&name_buffer);
    while (event) |ev| : (event = try instance.get(&name_buffer)) {
        std.debug.print("Event: {}\n", .{ev});
        std.debug.print("name: {s}\n", .{name_buffer[0..ev.len]});
    }
}
