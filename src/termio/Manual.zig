//! Manual is a termio backend with no process and no pty. The embedder owns the
//! other end of the "terminal connection": it feeds program output in with
//! Termio.processOutput (ghostty_surface_write_pty_output) and receives the
//! bytes the terminal would have written to the pty (keys, mouse, paste,
//! query replies) through the surface's pty input callback.
//!
//! This is for platforms that can't spawn processes, such as iOS, where the
//! terminal is connected to something remote (e.g. an SSH channel).
const Manual = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../apprt.zig");
const renderer = @import("../renderer.zig");
const terminal = @import("../terminal/main.zig");
const termio = @import("../termio.zig");
const ProcessInfo = @import("../pty.zig").ProcessInfo;

pub const Config = struct {};

pub fn init(alloc: Allocator, cfg: Config) !Manual {
    _ = alloc;
    _ = cfg;
    return .{};
}

pub fn deinit(self: *Manual) void {
    _ = self;
}

pub fn initTerminal(self: *Manual, t: *terminal.Terminal) void {
    _ = self;
    _ = t;
}

pub fn threadEnter(
    self: *Manual,
    alloc: Allocator,
    io: *termio.Termio,
    td: *termio.Termio.ThreadData,
) !void {
    _ = self;
    _ = alloc;
    _ = io;
    td.backend = .{ .manual = .{} };
}

pub fn threadExit(self: *Manual, td: *termio.Termio.ThreadData) void {
    _ = self;
    _ = td;
}

pub fn focusGained(
    self: *Manual,
    td: *termio.Termio.ThreadData,
    focused: bool,
) !void {
    _ = self;
    _ = td;
    _ = focused;
}

pub fn resize(
    self: *Manual,
    grid_size: renderer.GridSize,
    screen_size: renderer.ScreenSize,
) !void {
    // The embedder tells the remote side about size changes itself.
    _ = self;
    _ = grid_size;
    _ = screen_size;
}

/// Hand bytes the terminal would write to the pty to the embedder. With
/// `linefeed` (LNM mode), CR is sent as CRLF, as Exec does.
pub fn queueWrite(
    self: *Manual,
    alloc: Allocator,
    td: *termio.Termio.ThreadData,
    data: []const u8,
    linefeed: bool,
) !void {
    _ = self;
    _ = alloc;
    if (!linefeed) {
        writeToEmbedder(td, data);
        return;
    }

    var buf: [256]u8 = undefined;
    var len: usize = 0;
    for (data) |ch| {
        if (len + 2 > buf.len) {
            writeToEmbedder(td, buf[0..len]);
            len = 0;
        }
        buf[len] = ch;
        len += 1;
        if (ch == '\r') {
            buf[len] = '\n';
            len += 1;
        }
    }
    if (len > 0) writeToEmbedder(td, buf[0..len]);
}

fn writeToEmbedder(td: *termio.Termio.ThreadData, data: []const u8) void {
    if (data.len == 0) return;
    // Only the embedded apprt has an input callback; other runtimes never
    // select this backend.
    if (comptime !@hasField(apprt.runtime.Surface, "pty_input_callback")) return;
    const rt_surface = td.surface_mailbox.surface.rt_surface;
    const callback = rt_surface.pty_input_callback orelse return;
    callback(rt_surface.userdata, data.ptr, data.len);
}

pub fn childExitedAbnormally(
    self: *Manual,
    gpa: Allocator,
    t: *terminal.Terminal,
    exit_code: u32,
    runtime_ms: u64,
) !void {
    _ = self;
    _ = gpa;
    _ = t;
    _ = exit_code;
    _ = runtime_ms;
}

pub fn getProcessInfo(self: *Manual, comptime info: ProcessInfo) ?ProcessInfo.Type(info) {
    _ = self;
    return null;
}

pub const ThreadData = struct {
    pub fn deinit(self: *ThreadData, alloc: Allocator) void {
        _ = self;
        _ = alloc;
    }
};
