const std = @import("std");
const print = std.debug.print;

pub const Socket = struct {
    address: std.net.Address,
    socket: std.posix.socket_t,

    pub fn init(ip: []const u8, port: u16) !Socket {
        const socket_t = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0);
        errdefer std.posix.close(socket_t);
        const address = try std.net.Address.parseIp4(ip, port);
        return Socket{ .address = address, .socket = socket_t };
    }

    pub fn bind(self: *Socket) !void {
        try std.posix.bind(self.socket, &self.address.any, self.address.getOsSockLen());
    }
};