# Closure.zig
Now we can use closure in zig ;)
## Example: up value support
```zig
    var val: i32 = 100;
    var clo = Closure.make(&.{ .pval = &val }, struct {
        pub fn call(up: anytype) void {
            up.pval.* = 400;
        }
    });
    try clo.call(.{});
    try t.expect(val == 400);
```
## Example: up value + call argument
```zig
    var val: i32 = 100;
    var clo = Closure.make(&.{ .pval = &val }, struct {
        pub fn call(up: anytype, new_val: i32) void {
            up.pval.* = new_val;
        }
    });
    try clo.call(&.{@as(i32, 900)});
    try t.expect(val == 900);
```
## Example: up value on heap
```zig
    const t = std.testing;
    var val: i32 = 100;
    var clo = Closure.new(t.allocator, &.{ .pval = &val }, struct {
        pub fn call(up: anytype, new_val: i32) void {
            up.pval.* = new_val;
        }
    });
    defer clo.deinit();
    try clo.call(&.{@as(i32, 900)});
    try t.expect(val == 900);
```

## Example: Make the parameters of the closure clearly readable
```zig
    var val:i32 = 100;
    var clo:Closure.Of(fn (new_val: i32) void) = Closure.make(&.{ .pval = &val }, struct {
        pub fn call(up: anytype, new_val: i32) void {
            up.pval.* = new_val;
        }
    });
    try clo.call(&.{@as(i32, 400)});
    try t.expect(val == 400);
```

## Example: Optional deinit function
You can define an optional `deinit` function in your Func struct. It will be called when the closure is deinitialized, before the memory is freed (for heap closures) or before the ptr is set to null (for stack closures).

```zig
    const Data = struct {
        age: i32,
        name: []const u8,
    };
    var data: Data = .{ .age = 10, .name = "default" };
    
    var clo = Closure.new(t.allocator, &.{ .data = &data }, struct {
        pub fn call(up: anytype, new_age: i32, new_name: []const u8) void {
            up.data.* = .{ .age = new_age, .name = new_name };
        }
        pub fn deinit(up: anytype) void {
            up.data.* = .{ .age = 0, .name = "deinitialized" };
        }
    });
    try clo.call(&.{ @as(i32, 80), @as([]const u8, "hello") });
    clo.deinit();
    // deinit function was called
    try t.expectEqualStrings(data.name, "deinitialized");
```

## Example: Error handling
The `call` method returns `!void` and will return `error.Deinitialized` if the closure has already been deinitialized.

```zig
    var clo = Closure.new(t.allocator, &.{ .data = &data }, struct {
        pub fn call(up: anytype) void {
            // ...
        }
    });
    clo.deinit();
    // Now calling clo.call() will return an error
    const result = clo.call(.{});
    try t.expectError(error.Deinitialized, result);
```

More examples in source code: [here](src/root.zig) 