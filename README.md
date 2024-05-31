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
    // note:arg must be the first parameter and the type must be calculated with ArgType.
    //      parameter[1..] for upvalue (5 => pa, 6 => pb).
    clo = Closure.init(t.allocator, struct {
        pub fn func(arg: ArgType(.{ *i32, *i64 }), va: i32, vb: i64) void {
            arg[0].* = va;
            arg[1].* = vb;
        }
    }, .{ 5, 6 });
    clo.call(.{ &a, &b });
    clo.deinit();
    try t.expect(a == 5 and b == 6);
```
More examples in source code: [here](src/root.zig) 