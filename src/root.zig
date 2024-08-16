const std = @import("std");
const Tuple = std.meta.Tuple;
const StructField = std.builtin.Type.StructField;

// call with this arg means deinit.
const destroy_arg = "destroy me";

const Closure = @This();

ptr: ?*anyopaque,
pfunc: *const fn (?*anyopaque, ?[*]const u8) void,

/// Helping to declare closure parameter types simply does the only thing that makes the code readable
/// example:
/// var clo: Closure.Of(.{.arg = .{.name = []const u8, .index = i32, .ret = *bool}),
pub fn Of(args_declare: anytype) type {
    _ = args_declare;
    return Closure;
}

pub fn init(ally: std.mem.Allocator, func_or_struct: anytype, up_values: anytype) Closure {
    return ClosureType(FuncType(func_or_struct), @TypeOf(up_values)).init(ally, funcValue(func_or_struct), up_values);
}

pub fn make(func_or_struct: anytype, p_upvalue: anytype) Closure {
    if (@TypeOf(p_upvalue) == @TypeOf(null) or @TypeOf(p_upvalue) == @TypeOf(.{})) {
        return .{ .ptr = null, .pfunc = StackClosureCaller(funcValue(func_or_struct), @TypeOf(.{})).func };
    } else {
        if (@typeInfo(@TypeOf(p_upvalue)) != .Pointer) @compileError("upvalue for make() must be pointer.");
        return .{ .ptr = @ptrCast(@constCast(p_upvalue)), .pfunc = StackClosureCaller(funcValue(func_or_struct), @TypeOf(p_upvalue.*)).func };
    }
}

pub fn call(self: Closure, arg: anytype) void {
    const TArg = @TypeOf(arg);
    if (TArg == @TypeOf(.{}) or TArg == @TypeOf(null)) {
        self.pfunc(self.ptr, null);
    } else {
        if (isComptimeTypeTuple(TArg)) @compileError("must use Closure.callTyped() if the arg has any comptime field.");
        const buf: [*]const u8 = @ptrCast(@alignCast(&arg));
        self.pfunc(self.ptr, buf);
    }
}

pub fn callTyped(self: Closure, comptime T: type, arg: T) void {
    self.call(arg);
}

pub fn deinit(self: Closure) void {
    self.pfunc(self.ptr, destroy_arg.ptr);
}

fn FuncType(any: anytype) type {
    const T = @TypeOf(any);
    comptime var ret: type = void;
    comptime var err: []const u8 = "";
    const typeinfo = if (T == type) @typeInfo(any) else @typeInfo(T);
    switch (typeinfo) {
        .Struct => |info| {
            if (info.decls.len != 1) {
                err = "expect struct with just one function.";
            } else {
                const field = @field(any, info.decls[0].name);
                if (@typeInfo(@TypeOf(field)) != .Fn) {
                    err = std.fmt.comptimePrint("{s}.{s} is not a function.", .{ @typeName(T), info.decls[0].name });
                } else {
                    ret = @TypeOf(field);
                }
            }
        },
        .Fn => ret = T,
        else => err = "expect struct or function but got " ++ @typeName(T),
    }
    if (ret == void) @compileError(err) else return ret;
}

fn funcValue(any: anytype) FuncType(any) {
    comptime {
        switch (@typeInfo(@TypeOf(any))) {
            .Fn => return any,
            .Type => return @field(any, @typeInfo(any).Struct.decls[0].name),
            else => {},
        }
    }
}

inline fn isTypeTuple(comptime T: type) bool {
    switch (@typeInfo(T)) {
        .Struct => |info| {
            if (info.is_tuple == false) return false;
            inline for (info.fields) |field| {
                if (@TypeOf(field.type) != type) return false;
            }
            return true;
        },
        else => return T == @TypeOf(.{}),
    }
}

inline fn isComptimeTypeTuple(comptime T: type) bool {
    if (isTypeTuple(T) == false) return false;
    if (T == @TypeOf(.{})) return false;
    inline for (@typeInfo(T).Struct.fields) |field| {
        if (field.is_comptime) return true;
    }
    return false;
}

fn StackClosureCaller(function: anytype, comptime TUpValue: type) type {
    const TFunc = FuncType(function);
    const has_arg = FuncArgType(TFunc) != void;
    if (has_arg) {
        return t: {
            if (TUpValue == @TypeOf(.{})) break :t struct {
                pub fn func(_: ?*anyopaque, arg: ?[*]const u8) void {
                    if (arg) |p| {
                        if (@intFromPtr(p) == @intFromPtr(destroy_arg.ptr)) return;
                    }
                    const real_arg: *FuncArgType(TFunc) = @ptrCast(@alignCast(@constCast(arg.?)));
                    @call(.auto, function, .{real_arg.*});
                }
            } else break :t struct {
                pub fn func(p_upvalue: ?*anyopaque, arg: ?[*]const u8) void {
                    if (arg) |p| {
                        if (@intFromPtr(p) == @intFromPtr(destroy_arg.ptr)) return;
                    }
                    const real_arg: *FuncArgType(TFunc) = @ptrCast(@alignCast(@constCast(arg.?)));
                    const upvalue: *TUpValue = @ptrCast(@alignCast(@constCast(p_upvalue.?)));
                    @call(.auto, function, .{real_arg.*} ++ upvalue.*);
                }
            };
        };
    } else {
        return t: {
            if (TUpValue == @TypeOf(.{})) break :t struct {
                pub fn func(_: ?*anyopaque, arg: ?[*]const u8) void {
                    if (arg) |p| {
                        if (@intFromPtr(p) == @intFromPtr(destroy_arg.ptr)) return;
                    }
                    @call(.auto, function, .{});
                }
            } else break :t struct {
                pub fn func(p_upvalue: ?*anyopaque, arg: ?[*]const u8) void {
                    if (arg) |p| {
                        if (@intFromPtr(p) == @intFromPtr(destroy_arg.ptr)) return;
                    }
                    const upvalue: *TUpValue = @ptrCast(@alignCast(p_upvalue.?));
                    @call(.auto, function, upvalue.*);
                }
            };
        };
    }
}

fn FuncArgType(comptime TFunc: type) type {
    const info = @typeInfo(TFunc);
    if (info != .Fn) @compileError("pfunc is not a .Fn");

    if (info.Fn.params.len == 0) return void;
    const T0 = info.Fn.params[0].type.?;
    return if (isTypeTuple(T0)) T0 else void;
}

fn FuncUpValueTuple(comptime TFunc: type) type {
    const info = @typeInfo(TFunc);
    if (info != .Fn) @compileError("pfunc is not a .Fn");
    const len = info.Fn.params.len;
    if (len == 0) return @TypeOf(.{});

    const has_arg = isTypeTuple(info.Fn.params[0].type.?);
    if (has_arg and len == 1) {
        return @TypeOf(.{});
    }
    const start = if (has_arg) 1 else 0;
    const reallen = if (has_arg) len - 1 else len;

    comptime var fields: [reallen]StructField = undefined;
    inline for (info.Fn.params[start..], 0..) |p, i| {
        fields[i] = .{
            .name = std.fmt.comptimePrint("{}", .{i}),
            .type = p.type.?,
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(p.type.?),
        };
    }

    return @Type(.{ .Struct = .{
        .layout = .auto,
        .fields = fields[0..reallen],
        .decls = &.{},
        .is_tuple = true,
    } });
}

fn typesLen(comptime types: anytype) comptime_int {
    comptime var len = 0;
    inline for (types) |_| {
        len += 1;
    }
    return len;
}

fn Invoker(comptime Caller: type) type {
    const TFunc = std.meta.Child(std.meta.FieldType(Caller, .func));
    const has_arg = FuncArgType(TFunc) != void;
    if (has_arg) {
        if (@hasField(Caller, "upvalue")) {
            return struct {
                pub fn invoke(self: *Caller, arg: ?[*]const u8) void {
                    const real_arg: *FuncArgType(TFunc) = @ptrCast(@alignCast(@constCast(arg.?)));
                    @call(.auto, self.func, .{real_arg.*} ++ self.upvalue);
                }
            };
        } else {
            return struct {
                pub fn invoke(self: *Caller, arg: ?[*]const u8) void {
                    const real_arg: *FuncArgType(TFunc) = @ptrCast(@alignCast(@constCast(arg.?)));
                    @call(.auto, self.func, .{real_arg.*});
                }
            };
        }
    } else {
        if (@hasField(Caller, "upvalue")) {
            return struct {
                pub fn invoke(self: *Caller, _: ?[*]const u8) void {
                    @call(.auto, self.func, self.upvalue);
                }
            };
        } else {
            return struct {
                pub fn invoke(self: *Caller, _: ?[*]const u8) void {
                    @call(.auto, self.func, .{});
                }
            };
        }
    }
}

fn ClosureType(comptime TFunc: type, comptime TUpValue: type) type {
    const Caller = t: {
        if (TUpValue == @TypeOf(.{})) break :t struct {
            func: *const TFunc,
            pub fn init(f: *const TFunc, _: TUpValue) @This() {
                return .{ .func = f };
            }

            pub fn invoke(self: *@This(), arg: ?[*]const u8) void {
                Invoker(@This()).invoke(self, arg);
            }
        } else break :t struct {
            func: *const TFunc,
            upvalue: TUpValue,

            pub fn init(f: *const TFunc, upvalue: TUpValue) @This() {
                return .{ .func = f, .upvalue = upvalue };
            }
            pub fn invoke(self: *@This(), arg: ?[*]const u8) void {
                Invoker(@This()).invoke(self, arg);
            }
        };
    };

    const upvalue_len = switch (@typeInfo(TUpValue)) {
        .Struct => |info| info.fields.len,
        else => 0,
    };

    return struct {
        const Self = @This();

        caller: Caller,
        deallocator: std.mem.Allocator,

        pub fn init(ally: std.mem.Allocator, pfunc: *const TFunc, args: anytype) Closure {
            const self = ally.create(Self) catch @panic("OOM");
            var upvalue: TUpValue = undefined;
            inline for (0..upvalue_len) |i| {
                upvalue[i] = args[i];
            }
            self.* = .{ .caller = Caller.init(pfunc, upvalue), .deallocator = ally };
            return .{ .ptr = self, .pfunc = @ptrCast(&invoke) };
        }

        fn invoke(self: *Self, arg: ?[*]const u8) void {
            if (arg) |a| {
                if (@intFromPtr(a) == @intFromPtr(destroy_arg.ptr)) {
                    self.deallocator.destroy(self);
                    return;
                }
            }
            self.caller.invoke(arg);
        }
    };
}

test "closure" {
    const t = std.testing;

    var a: i32 = 0;
    var b: i64 = 0;

    // test upvalue.
    // .{ &a, 1 } for: &a => p, 1 => v
    var clo = Closure.init(t.allocator, struct {
        pub fn func(p: *i32, v: i32) void {
            p.* = v;
        }
    }, .{ &a, 1 });
    clo.call(.{});
    clo.deinit();
    try t.expect(a == 1);

    // test arg.
    // .{ &b, 2 } for: &b => arg[0], 2 => arg[1]
    // note: because 2 is comptime value, so we need use callTyped() here.
    clo = Closure.init(t.allocator, struct {
        pub fn func(arg: Tuple(&.{ *i64, i64 })) void {
            arg[0].* = arg[1];
        }
    }, .{});
    clo.callTyped(Tuple(&.{ *i64, i64 }), .{ &b, 2 });
    clo.deinit();
    try t.expect(b == 2);

    // test upvalue + arg
    // note:arg must be the first parameter and the type must be calculated with ArgType.
    //      parameter[1..] for upvalue (&a => pa, &b => pb).
    clo = Closure.init(t.allocator, struct {
        pub fn func(arg: Tuple(&.{ i32, i64 }), pa: *i32, pb: *i64) void {
            pa.* = arg[0];
            pb.* = arg[1];
        }
    }, .{ &a, &b });
    clo.callTyped(Tuple(&.{ i32, i64 }), .{ 3, 4 });
    clo.deinit();
    try t.expect(a == 3 and b == 4);

    // test no comptime arg call.
    clo = Closure.init(t.allocator, struct {
        pub fn func(arg: Tuple(&.{ *i32, *i64 }), va: i32, vb: i64) void {
            arg[0].* = va;
            arg[1].* = vb;
        }
    }, .{ 5, 6 });
    clo.call(.{ &a, &b });
    clo.deinit();
    try t.expect(a == 5 and b == 6);

    //test stack upvalue
    clo = Closure.make(struct {
        pub fn func(pa: *i32, pb: *i64) void {
            pa.* = 7;
            pb.* = 8;
        }
    }, &.{ &a, &b });
    clo.call(null);
    try t.expect(a == 7 and b == 8);

    //test stack upvalue with call arg
    clo = Closure.make(struct {
        pub fn func(arg: Tuple(&.{ *i32, *i64 }), va: i32, vb: i64) void {
            const pa, const pb = arg;
            pa.* = va;
            pb.* = vb;
        }
    }, &Tuple(&.{ i32, i64 }){ 9, 10 });
    clo.call(.{ &a, &b });
    try t.expect(a == 9 and b == 10);

    //test stack upvalue with upvalue == null
    clo = Closure.make(struct {
        pub fn func(arg: Tuple(&.{*i32})) void {
            arg[0].* = 11;
        }
    }, &.{});
    clo.call(.{&a});
    try t.expect(a == 11);

    clo = Closure.make(struct {
        pub fn func(out: *i32, nums: []const i32) void {
            out.* = 0;
            for (nums) |n| {
                out.* += n;
            }
        }
    }, &.{ &a, &.{ 1, 2, 3, 4, 5 } });
    clo.call(null);
    try t.expect(a == 1 + 2 + 3 + 4 + 5);

    a = 0;
    clo = Closure.make(rawfunc, &.{ &a, &.{ 1, 2, 3, 4, 5 } });
    clo.call(null);
    try t.expect(a == 1 + 2 + 3 + 4 + 5);
}

fn rawfunc(out: *i32, nums: []const i32) void {
    out.* = 0;
    for (nums) |n| {
        out.* += n;
    }
}
