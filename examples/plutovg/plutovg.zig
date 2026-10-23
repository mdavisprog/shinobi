const std = @import("std");

pub const pi = 3.14159265358979323846;
pub const two_pi = 6.28318530717958647693;
pub const half_pi = 1.57079632679489661923;
pub const sqrt2 = 1.41421356237309504880;
pub const kappa = 0.55228474983079339840;

pub const DestroyFunc = *const fn (closure: ?*anyopaque) void;
pub const Canvas = anyopaque;
pub const Surface = anyopaque;

pub const Color = extern struct {
    r: f32 = 0.0,
    g: f32 = 0.0,
    b: f32 = 0.0,
    a: f32 = 0.0,

    pub fn init(r: f32, g: f32, b: f32, a: f32) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }
};

pub fn version() i32 {
    return @intCast(plutovg_version());
}

pub fn versionString() [*c]const u8 {
    const result = plutovg_version_string();
    return std.mem.span(result);
}

pub fn surfaceCreate(width: i32, height: i32) *Surface {
    return plutovg_surface_create(@intCast(width), @intCast(height));
}

pub fn surfaceDestroy(surface: *Surface) void {
    plutovg_surface_destroy(surface);
}

pub fn surfaceGetData(surface: *const Surface) []const u8 {
    const stride = surfaceGetStride(surface);
    const height = surfaceGetHeight(surface);
    const len: usize = @intCast(stride * height);
    const data = plutovg_surface_get_data(surface);
    return data[0..len];
}

pub fn surfaceGetWidth(surface: *const Surface) i32 {
    return @intCast(plutovg_surface_get_width(surface));
}

pub fn surfaceGetHeight(surface: *const Surface) i32 {
    return @intCast(plutovg_surface_get_height(surface));
}

pub fn surfaceGetStride(surface: *const Surface) i32 {
    return @intCast(plutovg_surface_get_stride(surface));
}

pub fn surfaceWriteToPNG(surface: *const Surface, filename: []const u8) bool {
    return plutovg_surface_write_to_png(surface, filename.ptr);
}

pub fn canvasCreate(surface: *Surface) *Canvas {
    return plutovg_canvas_create(surface);
}

pub fn canvasDestroy(canvas: *Canvas) void {
    plutovg_canvas_destroy(canvas);
}

pub fn canvasSave(canvas: *Canvas) void {
    plutovg_canvas_save(canvas);
}

pub fn canvasRestore(canvas: *Canvas) void {
    plutovg_canvas_restore(canvas);
}

pub fn canvasSetRGB(canvas: *Canvas, r: f32, g: f32, b: f32) void {
    plutovg_canvas_set_rgb(canvas, r, g, b);
}

pub fn canvasSetLineWidth(canvas: *Canvas, line_width: f32) void {
    plutovg_canvas_set_line_width(canvas, line_width);
}

pub fn canvasArc(canvas: *Canvas, cx: f32, cy: f32, r: f32, a0: f32, a1: f32, ccw: bool) void {
    plutovg_canvas_arc(canvas, cx, cy, r, a0, a1, ccw);
}

pub fn canvasFill(canvas: *Canvas) void {
    plutovg_canvas_fill(canvas);
}

pub fn canvasStroke(canvas: *Canvas) void {
    plutovg_canvas_stroke(canvas);
}

pub fn canvasFillPreserve(canvas: *Canvas) void {
    plutovg_canvas_fill_preserve(canvas);
}

extern fn plutovg_version() c_int;
extern fn plutovg_version_string() [*c]const u8;
extern fn plutovg_surface_create(width: c_int, height: c_int) *Surface;
extern fn plutovg_surface_destroy(surface: *Surface) void;
extern fn plutovg_surface_get_data(surface: *const Surface) [*c]const u8;
extern fn plutovg_surface_get_width(surface: *const Surface) c_int;
extern fn plutovg_surface_get_height(surface: *const Surface) c_int;
extern fn plutovg_surface_get_stride(surface: *const Surface) c_int;
extern fn plutovg_surface_write_to_png(surface: *const Canvas, filename: [*c]const u8) bool;
extern fn plutovg_canvas_create(surface: *Surface) *Canvas;
extern fn plutovg_canvas_destroy(canvas: *Canvas) void;
extern fn plutovg_canvas_save(canvas: *Canvas) void;
extern fn plutovg_canvas_restore(canvas: *Canvas) void;
extern fn plutovg_canvas_set_rgb(canvas: *Canvas, r: f32, g: f32, b: f32) void;
extern fn plutovg_canvas_set_line_width(canvas: *Canvas, line_width: f32) void;
extern fn plutovg_canvas_arc(canvas: *Canvas, cx: f32, cy: f32, r: f32, a0: f32, a1: f32, ccw: bool) void;
extern fn plutovg_canvas_fill(canvas: *Canvas) void;
extern fn plutovg_canvas_stroke(canvas: *Canvas) void;
extern fn plutovg_canvas_fill_preserve(canvas: *Canvas) void;
