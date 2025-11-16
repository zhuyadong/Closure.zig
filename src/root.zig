const std = @import("std");
const StructField = std.builtin.Type.StructField;

// call with this arg means deinit.
const destroy_arg = "destroy me";

const Closure = @This();

pub const Error = error{
    Deinitialized,
};

ptr: ?*anyopaque,
pfunc: *const fn (*Closure, *anyopaque, ?*anyopaque) anyerror!void,

// declare closure type for code reader, ex: Of(fn (n: i32) void)
pub fn Of(_: anytype) type {
    return Closure;
}

pub fn new(allocator: std.mem.Allocator, up: anytype, Func: type) std.mem.Allocator.Error!Closure {
    const T = OfHeap(@TypeOf(up.*), Func);
    const data: *T = try allocator.create(T);
    data.upValues = up.*;
    data.allocator = allocator;
    return .{
        .ptr = @ptrCast(data),
        .pfunc = &T.call,
    };
}

pub fn make(up: anytype, Func: type) Closure {
    const T = OfStack(@TypeOf(up.*), Func);
    return .{
        .ptr = @ptrCast(@constCast(up)),
        .pfunc = &T.call,
    };
}

pub fn deinit(self: *Closure) void {
    if (self.ptr) |ptr| {
        _ = self.pfunc(self, ptr, @ptrCast(@constCast(destroy_arg.ptr))) catch unreachable;
    }
}

pub fn call(self: *Closure, args: anytype) !void {
    if (self.ptr == null) {
        return Error.Deinitialized;
    }
    if (comptime @TypeOf(args) == @TypeOf(.{})) {
        try self.pfunc(self, self.ptr.?, null);
    } else {
        var fixargs = removeComptime(args.*);
        try self.pfunc(self, self.ptr.?, @ptrCast(&fixargs));
    }
}

fn OfHeap(UpValues: type, Func: type) type {
    const ArgType = FuncArgTuple(Func);
    return struct {
        allocator: std.mem.Allocator,
        upValues: UpValues,
        pub fn call(clo: *Closure, pself: *const anyopaque, parg: ?*const anyopaque) !void {
            const self: *@This() = @ptrCast(@alignCast(@constCast(pself)));
            if (parg) |arg| {
                if (@intFromPtr(arg) == @intFromPtr(destroy_arg.ptr)) {
                    if (comptime @hasDecl(Func, "deinit")) {
                        Func.deinit(&self.upValues);
                    }
                    self.allocator.destroy(self);
                    clo.ptr = null;
                    return;
                }
            }
            if (comptime ArgType == @TypeOf(.{})) {
                try Func.call(&self.upValues);
            } else {
                const real_arg: *ArgType = @ptrCast(@alignCast(@constCast(parg.?)));
                try @call(.auto, Func.call, .{&self.upValues} ++ real_arg.*);
            }
        }
    };
}

fn OfStack(UpValues: type, Func: type) type {
    const ArgType = FuncArgTuple(Func);
    return struct {
        pub fn call(clo: *Closure, upValues: *const anyopaque, parg: ?*const anyopaque) !void {
            const args: *UpValues = @ptrCast(@alignCast(@constCast(upValues)));
            if (parg) |arg| {
                if (@intFromPtr(arg) == @intFromPtr(destroy_arg.ptr)) {
                    if (comptime @hasDecl(Func, "deinit")) {
                        Func.deinit(args);
                    }
                    clo.ptr = null;
                    return;
                }
            }

            if (comptime ArgType == @TypeOf(.{})) {
                try Func.call(args);
            } else {
                const real_arg: *ArgType = @ptrCast(@alignCast(@constCast(parg.?)));
                try @call(.auto, Func.call, .{args} ++ real_arg.*);
            }
        }
    };
}

fn FuncArgTuple(comptime TFunc: type) type {
    const info = @typeInfo(@TypeOf(TFunc.call));
    if (info != .@"fn") @compileError("pfunc is not a .@\"fn\"");
    const len = info.@"fn".params.len;
    if (len < 2) return @TypeOf(.{});

    comptime var fields: [len - 1]StructField = undefined;
    inline for (info.@"fn".params[1..], 0..) |p, i| {
        fields[i] = .{
            .name = std.fmt.comptimePrint("{}", .{i}),
            .type = p.type.?,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = fields[0 .. len - 1],
        .decls = &.{},
        .is_tuple = true,
    } });
}

fn RemoveComptime(comptime T: type) type {
    const info = @typeInfo(T);
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("Expected tuple type, got " ++ @typeName(T));
    }

    comptime var fields: [info.@"struct".fields.len]std.builtin.Type.StructField = undefined;
    inline for (info.@"struct".fields, 0..) |field, i| {
        fields[i] = .{
            .name = field.name,
            .type = field.type,
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = 0,
        };
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = &fields,
            .decls = &.{},
            .is_tuple = true,
        },
    });
}

fn removeComptime(tuple: anytype) RemoveComptime(@TypeOf(tuple)) {
    const T = @TypeOf(tuple);
    const info = @typeInfo(T);
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("Expected tuple type, got " ++ @typeName(T));
    }

    var result: RemoveComptime(T) = undefined;
    inline for (info.@"struct".fields, 0..) |_, i| {
        result[i] = tuple[i];
    }
    return result;
}

test "Closure" {
    const t = std.testing;

    // no arg closure
    var val: i32 = 100;
    var clo = make(&.{ .pval = &val }, struct {
        pub fn call(up: anytype) !void {
            up.pval.* = 400;
        }
    });
    try clo.call(.{});
    try t.expect(val == 400);

    // closure with args
    const Data = struct {
        age: i32,
        name: []const u8,
    };
    var data: Data = .{ .age = 10, .name = "default" };

    // stack clsure
    // decalre type make reader & editor happy
    var clo2: Closure.Of(fn (new_age: i32, new_name: []const u8) void) = undefined;
    clo2 = make(&.{ .data = &data }, struct {
        pub fn call(up: anytype, new_age: i32, new_name: []const u8) !void {
            up.data.* = .{ .age = new_age, .name = new_name };
        }
    });
    try clo2.call(&.{ @as(i32, 20), @as([]const u8, "changed") });
    try t.expect(data.age == 20);
    try t.expectEqualStrings(data.name, "changed");

    // heap closure
    clo2 = try new(t.allocator, &.{ .data = &data }, struct {
        pub fn call(up: anytype, new_age: i32, new_name: []const u8) !void {
            up.data.* = .{ .age = new_age, .name = new_name };
        }
        pub fn deinit(up: anytype) void {
            up.data.* = .{ .age = 0, .name = "deinitialized" };
        }
    });
    try clo2.call(&.{ @as(i32, 80), @as([]const u8, "hello") });
    try t.expect(data.age == 80);
    try t.expectEqualStrings(data.name, "hello");

    // test null pointer check
    clo2.deinit();
    try t.expect(clo2.ptr == null);
    try t.expectEqualStrings(data.name, "deinitialized");
    const result = clo2.call(&.{ @as(i32, 100), @as([]const u8, "test") });
    try t.expectError(error.Deinitialized, result);
}
