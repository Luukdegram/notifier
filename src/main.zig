const std = @import("std");

pub fn main() anyerror!void {
    std.log.info("All your codebase are belong to us.", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // open the current directory to watch
    var cwd = try std.process.getCwdAlloc(&gpa.allocator);
    defer gpa.allocator.free(cwd);

    std.log.info("cwd: {s}\n", .{cwd});

    const EventMask = packed struct {
        access: bool = true,
        modify: bool = true,
        attrib: bool = true,
        close_write: bool = false,
        close_nowrite: bool = false,
        close: bool = true,
        open: bool = true,
        moved_from: bool = false,
        moved_to: bool = false,
        moved: bool = true,
        create: bool = true,
        delete: bool = true,
        delete_self: bool = false,
        move_self: bool = true,

        // following fields are padded and should never be modified
        pad0: u1 = 0,
        pad1: u1 = 0,
        pad: u16 = 0,

        fn toInt(self: @This()) u32 {
            return @bitCast(u32, self);
        }
    };
    // setup inotify
    const instance = try std.os.inotify_init1(0);
    const handle = try std.os.inotify_add_watch(instance, "/home/luuk/projects/zoog/t.zig", (EventMask{}).toInt());

    var inotify = std.fs.File{ .handle = handle };

    var instance_fd = std.fs.File{ .handle = instance };

    const Event = extern struct {
        wd: i32,
        mask: u32,
        cookie: u32,
        len: u32,

        fn getMask(self: @This()) EventMask {
            return @bitCast(EventMask, self.mask);
        }
    };

    std.log.info("Event: {}\n", .{instance_fd.reader().readStruct(Event)});
}
