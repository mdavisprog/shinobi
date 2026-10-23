const plutovg = @import("plutovg");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    _ = init;

    std.log.info("Writing 'smiley.png' with plutovg version {s}!", .{plutovg.versionString()});

    const width = 150.0;
    const height = 150.0;

    const center_x = width / 2.0;
    const center_y = height / 2.0;
    const face_radius = 70.0;
    const mouth_radius = 50.0;
    const eye_radius = 10.0;
    const eye_offset_x = 25.0;
    const eye_offset_y = 20.0;
    const eye_x = center_x - eye_offset_x;
    const eye_y = center_y - eye_offset_y;

    const surface = plutovg.surfaceCreate(width, height);
    const canvas = plutovg.canvasCreate(surface);

    plutovg.canvasSave(canvas);
    plutovg.canvasArc(canvas, center_x, center_y, face_radius, 0.0, plutovg.two_pi, false);
    plutovg.canvasSetRGB(canvas, 1.0, 1.0, 0.0);
    plutovg.canvasFillPreserve(canvas);
    plutovg.canvasSetRGB(canvas, 0.0, 0.0, 0.0);
    plutovg.canvasSetLineWidth(canvas, 5.0);
    plutovg.canvasStroke(canvas);
    plutovg.canvasRestore(canvas);

    plutovg.canvasSave(canvas);
    plutovg.canvasArc(canvas, eye_x, eye_y, eye_radius, 0.0, plutovg.two_pi, false);
    plutovg.canvasArc(canvas, center_x + eye_offset_x, eye_y, eye_radius, 0.0, plutovg.two_pi, false);
    plutovg.canvasSetRGB(canvas, 0.0, 0.0, 0.0);
    plutovg.canvasFill(canvas);
    plutovg.canvasRestore(canvas);

    plutovg.canvasSave(canvas);
    plutovg.canvasArc(canvas, center_x, center_y, mouth_radius, 0.0, plutovg.pi, false);
    plutovg.canvasSetRGB(canvas, 0.0, 0.0, 0.0);
    plutovg.canvasSetLineWidth(canvas, 5.0);
    plutovg.canvasStroke(canvas);
    plutovg.canvasRestore(canvas);

    _ = plutovg.surfaceWriteToPNG(surface, "smiley.png");
    plutovg.canvasDestroy(canvas);
    plutovg.surfaceDestroy(surface);
}
