const std = @import("std");
const print = std.debug.print;
const root = @import("root");

/// This logger prints to file and stdErr simultaneously.
pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const file = std.fs.openFileAbsolute(root.log_path, .{ .mode = .read_write }) catch |err| {
        print("Failed to open log file: {}\n", .{err});
        return;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        print("Failed to get stat of log file: {}\n", .{err});
        return;
    };

    file.seekTo(stat.size) catch |err| {
        print("Failed to seek log file: {}\n", .{err});
        return;
    };

    const prefix = "[" ++ comptime level.asText() ++ "] " ++ "(" ++ @tagName(scope) ++ ") ";
    var buffer: [256]u8 = undefined;
    const message = std.fmt.bufPrint(buffer[0..], prefix ++ format ++ "\n", args) catch |err| {
        std.debug.print("Failed to format log message with args: {}\n", .{err});
        return;
    };
    file.writeAll(message) catch |err| {
        std.debug.print("Failed to write to log file: {}\n", .{err});
    };

    // Print the message to stderr, silently ignoring any errors
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format ++ "\n", args) catch return;
}