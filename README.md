# Closure.zig
Now we can use closure in zig ;)
## Example: up value support
```zig
const t = std.testing;

var a: i32 = 0;

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
```
## Example: up value + call argument
```zig
    const t = std.testing;

    var a: i32 = 0;
    var b: i64 = 0;
    // note:arg must be the first parameter and the type must be std.meta.Tuple.
    //      parameter[1..] for upvalue (5 => va, 6 => vb).
    clo = Closure.init(t.allocator, struct {
        pub fn func(arg: std.meta.Tuple(&.{ *i32, *i64 }), va: i32, vb: i64) void {
            arg[0].* = va;
            arg[1].* = vb;
        }
    }, .{ 5, 6 });
    clo.call(.{ &a, &b });
    clo.deinit();
    try t.expect(a == 5 and b == 6);
```
## Example: up value on stack
```zig
    //test upvalue on stack with call arg
    //Note: don't need to call clo.deinit() here, but it's safe to call and it's just do nothing.
    clo = Closure.make(struct {
        pub fn func(arg: std.meta.Tuple(&.{ *i32, *i64 }), va: i32, vb: i64) void {
            const pa, const pb = arg;
            pa.* = va;
            pb.* = vb;
        }
    }, &std.meta.Tuple(&.{ i32, i64 }){ 9, 10 });
    clo.call(.{ &a, &b });
    try t.expect(a == 9 and b == 10);
```
## Example: use invoke for return bool
```zig
    a = 0;
    clo = Closure.make(struct {
        pub fn func(arg: Tuple(&.{*i32})) bool {
            arg[0].* = 11;
            return false;
        }
    }, &.{});
    try t.expect(clo.invoke(.{&a}) == false);
    try t.expect(a == 11);

    clo = Closure.make(struct {
        pub fn func(arg: Tuple(&.{*i32})) void {
            arg[0].* = 11;
        }
    }, &.{});
    // invoke on void return function always return true
    try t.expect(clo.invoke(.{&a}) == true);
    try t.expect(a == 11);
```

## Example: Make the parameters of the closure clearly readable
```zig
const Data = struct {
    clo: Closure.Of(.{.arg32 = i32, .arg64 = i64, .ret = *i64}),
};
try std.testing.expect(@TypeOf(Data.clo) == Closure);
```
More examples in source code: [here](src/root.zig) 