const std = @import("std");
const os = std.os;
const Allocator = std.mem.Allocator;

/// Helper struct used to easily generate
/// a mask and provides safety to ensure unmatching
/// masks are not set at the same time
const WatchMask = packed struct {
    access: bool = false,
    modify: bool = false,
    attrib: bool = false,
    close_write: bool = false,
    close_nowrite: bool = false,
    close: bool = false,
    open: bool = false,
    moved_from: bool = false,
    moved_to: bool = false,
    moved: bool = false,
    create: bool = false,
    delete: bool = false,
    delete_self: bool = false,
    move_self: bool = false,

    // following fields are padded and should never be modified
    pad0: u1 = 0,
    pad1: u1 = 0,
    pad: u16 = 0,

    /// Returns the mask from the values set on the instance
    fn toInt(self: WatchMask) u32 {
        std.debug.assert(blk: {
            if (self.moved) break :blk !(self.moved_to or self.moved_from);
            if (self.moved_to or self.moved_from) break :blk !self.moved;

            if (self.close) break :blk !(self.close_write or self.close_nowrite);
            if (self.close_write or self.close_nowrite) break :blk !self.close;

            break :blk true;
        });
        return @bitCast(u32, self);
    }
};

const Self = @This();

instance: os.fd_t,
gpa: *Allocator,
watchers: std.ArrayListUnmanaged(os.fd_t),

/// Possible errors when initializes a new inotify instance
pub const InstanceInitError = error{
    /// Cannot have any more instances for the current process
    ProcessFdQuotaExceeded,
    /// Cannot have any more instances for the total system
    SystemFdQuotaExceeded,
    /// Not enough system resources
    SystemResources,
    /// An unexpected error occured
    Unexpected,
};

/// Initializes a new instance of inotify
pub fn init(flags: u32, gpa: *Allocator) InstanceInitError!Self {
    return Self{
        .instance = try os.inotify_init1(flags),
        .gpa = gpa,
        .watchers = std.ArrayListUnmanaged(os.fd_t),
    };
}

/// Possible errors when initializing additional watchers to the instance
pub const WatchInitError = error{
    AccessDenied,
    NameTooLong,
    FileNotFound,
    SystemResources,
    UserResourceLimitReached,
    OutOfMemory,
    UnexpectedError,
};

/// Adds a watcher to the inotify instance
pub fn addWatcher(self: Self, path: []const u8, mask: WatchMask) WatchInitError!void {
    try self.watchers.addOne(self.gpa).* = try os.inotify_add_watch(self.instance, path, mask.toInt());
}

comptime {
    std.debug.assert(@sizeOf(WatchMask) == 4);
    std.debug.assert((WatchMask{}).toInt() == 0);
}
