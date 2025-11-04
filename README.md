# Closure.zig
Now we can use closure in zig ;)
## Example: up value support
```zig
    var val: i32 = 100;
    var clo = Closure.make(.{ .pval = &val }, struct {
        pub fn call(up: anytype) void {
            up.pval.* = 400;
        }
    });
    clo.call(.{});
    try t.expect(val == 400);
```
## Example: up value + call argument
```zig
    var val: i32 = 100;
    var clo = Closure.make(.{ .pval = &val }, struct {
        pub fn call(up: anytype, new_val: i32) void {
            up.pval.* = new_val;
        }
    });
    clo.call(&.{@as(i32, 900)});
    try t.expect(val == 900);
```
## Example: up value on heap
```zig
    const t = std.testing;
    var val: i32 = 100;
    var clo = Closure.new(t.allocator, .{ .pval = &val }, struct {
        pub fn call(up: anytype, new_val: i32) void {
            up.pval.* = new_val;
        }
    });
    defer clo.deinit();
    clo.call(&.{@as(i32, 900)});
    try t.expect(val == 900);
```

## Example: Make the parameters of the closure clearly readable
```zig
    var val:i32 = 100;
    var clo:Closure.Of(fn (new_val: i32) void) = Closure.make(.{ .pval = &val }, struct {
        pub fn call(up: anytype, new_val: i32) void {
            up.pval.* = new_val;
        }
    });
    clo.call(.{@as(i32, 400)});
    try t.expect(val == 400);
```
More examples in source code: [here](src/root.zig) 