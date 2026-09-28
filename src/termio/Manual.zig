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

/// The apprt surface, for the embedder callbacks. Set in threadEnter.
rt_surface: ?*apprt.runtime.Surface = null,

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
    // The shell is remote (e.g. behind SSH) and we can't assume it redraws its
    // prompt after a resize, so don't clear prompt lines on resize unless the
    // shell opts in via OSC 133. Matches libghostty-vt's default for
    // embedders. With the upstream default, rotating a phone lost the prompt
    // line under bash.
    t.flags.shell_redraws_prompt = .false;
}

pub fn threadEnter(
    self: *Manual,
    alloc: Allocator,
    io: *termio.Termio,
    td: *termio.Termio.ThreadData,
) !void {
    _ = alloc;
    _ = io;
    self.rt_surface = td.surface_mailbox.surface.rt_surface;
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

/// Tell the embedder the terminal is being resized, so it can resize the remote
/// side (e.g. an SSH window change). This is the point where Exec sets the pty
/// size: it runs on the termio thread right before the terminal itself resizes,
/// after the resize coalescing delay. Telling the remote any earlier lets the
/// program's redraw for the new size arrive while the terminal still has the old
/// size (a 29-row frame clamped into 8 rows).
pub fn resize(
    self: *Manual,
    grid_size: renderer.GridSize,
    screen_size: renderer.ScreenSize,
) !void {
    if (comptime !@hasField(apprt.runtime.Surface, "pty_resize_callback")) return;
    const rt_surface = self.rt_surface orelse return;
    const callback = rt_surface.pty_resize_callback orelse return;
    callback(
        rt_surface.userdata,
        grid_size.columns,
        grid_size.rows,
        screen_size.width,
        screen_size.height,
    );
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
