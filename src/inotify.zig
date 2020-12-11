const std = @import("std");
const os = std.os;
const File = std.fs.File;
const Allocator = std.mem.Allocator;

/// Helper struct used to easily generate
/// a mask and provides safety to ensure unmatching
/// masks are not set at the same time
pub const WatchMask = packed struct {
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
    pad: u1 = 0,
    pad1: u1 = 0,
    pad2: u16 = 0,

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

/// Event struct containing the data when an event is triggered for inotify
pub const Event = extern struct {
    /// Watcher file descriptor
    wd: os.fd_t,
    /// Mask of the triggered event
    /// use getMask() to get a WatchMask instance
    mask: u32,
    /// Cookie can be used to track related events
    cookie: u32,
    /// Length of the name field, which contains the name of the file
    /// when the watcher is defined on a dictionary
    len: u32,
};

const Self = @This();

/// inotify instance file descriptor. Triggers the events the watchers have registered for
instance: File,
/// Allocator
gpa: *Allocator,
/// Watch list containing a list of file descriptors of the appended watchers
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
/// `flags` can be set to create a non-blocking version
pub fn init(gpa: *Allocator) InstanceInitError!Self {
    return Self{
        .instance = .{ .handle = try os.inotify_init1(os.linux.IN_NONBLOCK | os.linux.IN_CLOEXEC) },
        .gpa = gpa,
        .watchers = std.ArrayListUnmanaged(os.fd_t){},
    };
}

/// Closes all descriptors and frees memory
pub fn deinit(self: *Self) void {
    for (self.watchers.items) |w| {
        (File{ .handle = w }).close();
    }
    self.watchers.deinit(self.gpa);
    self.instance.close();
}

/// Removes a fd from the inotify instance and releases its resources
pub fn removeWatch(self: *Self, watch: os.fd_t) void {
    for (self.watchers.items) |w, i| {
        if (watch == w) {
            os.inotify_rm_watch(self.instance.handle, watch);
            _ = self.watchers.swapRemove(i);
            return;
        }
    }
}

/// Alias to os.ReadError for easier API
pub const ReadError = os.ReadError;

/// Returns the return type of a given function
fn ReturnTypeOf(comptime func: anytype) type {
    return @typeInfo(@TypeOf(func)).Fn.return_type.?;
}

/// Starts reading from the inotify instance file descriptor
/// returning the events to the given function
pub fn watch(self: *Self, comptime trigger: fn (Event, ?[]const u8) anyerror!void) ReadError!ReturnTypeOf(trigger) {
    const event_size = @sizeOf(Event);
    while (true) {
        var buffer: [event_size + std.fs.MAX_PATH_BYTES + 1]u8 = undefined;
        const len = os.read(self.instance.handle, &buffer) catch |err| switch (err) {
            error.WouldBlock => continue,
            else => return err,
        };
        if (len == 0) break;

        const event: Event = std.mem.bytesToValue(Event, buffer[0..event_size]);
        try if (event.len == 0)
            trigger(event, null)
        else
            trigger(event, buffer[event_size..len]);
    }
}

/// Possible errors when initializing additional watchers to the instance
pub const WatchInitError = error{
    /// No access to the directory/file
    AccessDenied,
    /// Given pathname is too long
    NameTooLong,
    /// File/Directory does not exist
    FileNotFound,
    /// Not enough system resources
    SystemResources,
    /// Too many open fd's
    UserResourceLimitReached,
    /// System out of memory
    OutOfMemory,
    /// An undocumented errorcode occured
    Unexpected,
};

/// Adds a watcher to the inotify instance
pub fn addWatcher(self: *Self, path: []const u8, mask: WatchMask) WatchInitError!void {
    (try self.watchers.addOne(self.gpa)).* = try os.inotify_add_watch(self.instance.handle, path, mask.toInt());
}

// ensures the WatchMask bitsize is correct due to buggy packed structs
comptime {
    std.debug.assert(@sizeOf(WatchMask) == 4);
    std.debug.assert((WatchMask{}).toInt() == 0);
}
