const std = @import("std");
const ArrayList = std.ArrayList;
const print = std.debug.print;

const Commands = enum(u8) {
    SELL = '0',
    BUY = '1',
    CANCEL_SELL = '3',
    CANCEL_BUY = '4',
    PRINT_BOOK_BUY = '5',
    PRINT_BOOK_SELL = '6',
};

const Order = struct {
    user: u32,
    quantity: u32,
    price: u32,
    timestamp: u32,
};

const Socket = struct {
    address: std.net.Address,
    socket: std.posix.socket_t,

    fn init(ip: []const u8, port: u16) !Socket {
        const socket_t = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.DGRAM, 0);
        errdefer std.posix.close(socket_t);
        const address = try std.net.Address.parseIp4(ip, port);
        return Socket{ .address = address, .socket = socket_t };
    }

    fn bind(self: *Socket) !void {
        try std.posix.bind(self.socket, &self.address.any, self.address.getOsSockLen());
    }
};

pub const std_options = .{
    // Set the log level to info
    .log_level = .debug,

    // Define logFn to override the std implementation
    .logFn = logFn,
};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const allocator = std.heap.page_allocator;
    const home = std.posix.getenv("HOME") orelse {
        print("Failed to read $HOME.\n", .{});
        return;
    };
    const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, ".local/share/zengine.log" }) catch |err| {
        print("Failed to create log file path: {}\n", .{err});
        return;
    };
    defer allocator.free(path);

    const file = std.fs.openFileAbsolute(path, .{ .mode = .read_write }) catch |err| {
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
}

pub fn main() !void {
    std.log.debug("This will not print.", .{});
    std.log.info("Application Started. Version 0.0.1", .{});
    std.log.err("Log file not found.", .{});
    // Setup
    // connection
    var sc = try Socket.init("127.0.0.1", 3001); // conection
    try sc.bind();
    // books
    var gba = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gba.allocator();

    var buy_book = ArrayList(Order).init(allocator);
    var sell_book = ArrayList(Order).init(allocator);

    var msg_buffer: [36]u8 = undefined; // mem. buffer
    while (true) {
        const received_bytes = try std.posix.recvfrom(sc.socket, msg_buffer[0..], 0, null, null);
        print("Received {d} bytes: {s}\n", .{ received_bytes, msg_buffer[0..received_bytes] });
        try parse_msg(msg_buffer[0..], &buy_book, &sell_book);
        match_orders(&buy_book, &sell_book);
    }
}

fn parse_msg(buf: []const u8, buy_book: *ArrayList(Order), sell_book: *ArrayList(Order)) !void {
    // NOTE: this is parseInt in development mode, but we may need to change
    // to std.mem.readInt(bigEndian / LittleEndian) on production.
    const order = buf[0];

    switch (order) {
        '0' => {
            print("SELL\n", .{});
            const new_order = Order{
                .user = try std.fmt.parseInt(u32, buf[1..3], 10),
                .price = try std.fmt.parseInt(u32, buf[3..5], 10),
                .quantity = try std.fmt.parseInt(u32, buf[5..7], 10),
                .timestamp = try std.fmt.parseInt(u32, buf[7..9], 10),
            };
            try parse_sell(sell_book, new_order);
        },
        '1' => {
            print("BUY\n", .{});
            const new_order = Order{
                .user = try std.fmt.parseInt(u32, buf[1..3], 10),
                .price = try std.fmt.parseInt(u32, buf[3..5], 10),
                .quantity = try std.fmt.parseInt(u32, buf[5..7], 10),
                .timestamp = try std.fmt.parseInt(u32, buf[7..9], 10),
            };
            try parse_buy(buy_book, new_order);
        },
        else => print("first byte: {}\n", .{order}),
    }
}

fn parse_buy(order_book: *ArrayList(Order), new_order: Order) !void {
    const len = order_book.items.len;
    if (len > 0) {
        for (0.., order_book.items) |i, order| {
            if (order.price >= new_order.price) continue;
            try order_book.insert(i, new_order);
            break;
        }
    } else {
        try order_book.append(new_order);
    }
    std.log.info("BUY Order: user {} qtd {}@{} on {}", .{ new_order.user, new_order.quantity, new_order.price, new_order.timestamp });
    print("Buy Book: {}\n", .{order_book});
}

fn parse_sell(order_book: *ArrayList(Order), new_order: Order) !void {
    const len = order_book.items.len;
    if (len > 0) {
        for (0.., order_book.items) |i, order| {
            if (order.price <= new_order.price) continue;
            try order_book.insert(i, new_order);
            break;
        }
    } else {
        try order_book.append(new_order);
    }
    std.log.info("SELL Order: user {} qtd {}@{} on {}", .{ new_order.user, new_order.quantity, new_order.price, new_order.timestamp });
    print("Sell Book: {}\n", .{order_book});
}

fn match_orders(buy_book: *ArrayList(Order), sell_book: *ArrayList(Order)) void {
    match: while (true) {
        const b_len = buy_book.items.len;
        const s_len = sell_book.items.len;
        if (b_len > 0 and s_len > 0) {
            var best_buy = buy_book.items[0];
            var best_sell = sell_book.items[0];
            if (best_buy.price >= best_sell.price) {
                if (best_sell.quantity == best_buy.quantity) {
                    const b_order = buy_book.orderedRemove(0);
                    const s_order = sell_book.orderedRemove(0);
                    print("user {} bought {} @ {}\n", .{ b_order.user, b_order.quantity, b_order.price });
                    print("user {} sold {} @ {}\n", .{ s_order.user, s_order.quantity, s_order.price });
                    continue :match;
                }
                const matched_quantity = @min(best_buy.quantity, best_sell.quantity);
                if (matched_quantity == best_buy.quantity) {
                    const b_order = buy_book.orderedRemove(0);
                    best_sell.quantity -= matched_quantity;

                    print("user {} bought {} @ {}\n", .{ b_order.user, b_order.quantity, b_order.price });
                }
                if (matched_quantity == best_sell.quantity) {
                    const s_order = buy_book.orderedRemove(0);
                    best_buy.quantity -= matched_quantity;
                    print("user {} sold {} @ {}\n", .{ s_order.user, s_order.quantity, s_order.price });
                }
            } else {
                print("No matching orders. Buy {}@{} | Sell {}@{}\n", .{ best_buy.quantity, best_buy.price, best_sell.quantity, best_sell.price });
                break :match;
            }
        } else {
            print("Empty book for buys or sells. No match possible\n", .{});
            break :match;
        }
    }
}
