package miniui

import "core:fmt"
import "core:math"
import plt "plot"

plot :: proc(ctx: ^Context, plot: ^plt.Plot, render_cmd := false, opt: Options = {.ALIGN_CENTER}) {
	// show the plot with wrappers for the geometry
	// send mouse interaction
	// right click for mode control popup menu
	opt := opt
	id := get_id(ctx, uintptr(plot))
	r := layout_next(ctx)
	update_control(ctx, id, r, opt)

	// BUG: If the size of the container has changed, then it needs to be re-rendered

	// TODO Handle scroll wheel zooming
	render_cmd := render_cmd

	plot_texture := Texture {
		texture_id = plot.framebuffer_rgb,
		width      = plot.framebuffer_width_max,
		height     = plot.framebuffer_height_max,
		inv_width  = 1.0 / f32(plot.framebuffer_width_max),
		inv_height = 1.0 / f32(plot.framebuffer_height_max),
	}

	// Queue the miniui command first so that the desired framebuffer size
	// is exactly known. Then the framebuffer is updated before the command
	// queue is executed in mu.draw().
	src := Rect{0, 0, min(r.w, plot_texture.width), min(r.h, plot_texture.height)}
	draw_image(ctx, plot_texture, r, src, color = {255, 255, 255, 255})

	@(static) render_first := true
	if render_cmd | render_first {
		plt.draw(ctx.plot_renderer, plot, r.w, r.h)
		render_first = false
	}

	@(static) mouse_start: Vec2

	if .RIGHT in ctx.mouse_pressed_bits && ctx.focus_id == id {
		mouse_start = ctx.mouse_pos
	}

	if .RIGHT in ctx.mouse_released_bits && ctx.last_id == id {
		mouse_move := ctx.mouse_pos - mouse_start
		if math.abs(mouse_move.x) > MOUSE_DRAG_TOLERANCE || math.abs(mouse_move.y) > MOUSE_DRAG_TOLERANCE {

			drag_start := plot_px_to_coords(plot, r, mouse_start)
			drag_end := plot_px_to_coords(plot, r, ctx.mouse_pos)

			if !plot.scale_auto_x {
				plot.range_x = {min(drag_start[0], drag_end[0]), max(drag_start[0], drag_end[0])}
			}
			if !plot.scale_auto_y {
				plot.range_y = {min(drag_start[1], drag_end[1]), max(drag_start[1], drag_end[1])}
			}

		} else {
			open_popup(ctx, "Plot#Context Menu")
		}
	}

	// LMB Interactions: Click-to-Drag
	if .LEFT in ctx.mouse_down_bits && ctx.focus_id == id {
		drag_delta: [2]f32
		drag_delta.x = f32(ctx.mouse_delta.x) * f32(plot.range_x[1] - plot.range_x[0]) / f32(r.w)
		drag_delta.y = f32(ctx.mouse_delta.y) * f32(plot.range_y[1] - plot.range_y[0]) / f32(r.h)
		if !plot.scale_auto_x {
			plot.range_x -= drag_delta.x
		}
		if !plot.scale_auto_y {
			plot.range_y += drag_delta.y
		}
	}

	// BUG Cuts off long text length
	if popup(ctx, "Plot#Context Menu") {
		if .SUBMIT in button(ctx, "reset zoom") {
			plt.scale_auto_x(plot)
			plt.scale_auto_y(plot)
		}
		checkbox(ctx, "Auto X", &plot.scale_auto_x)
		checkbox(ctx, "Auto Y", &plot.scale_auto_y)
	}
}


plot_px_to_coords :: proc(plot: ^plt.Plot, px_bounds: Rect, px_abs: Vec2) -> (result: [2]f32) {
	px_rel_x: f32 = f32(px_abs.x - px_bounds.x) / f32(px_bounds.w)
	px_rel_y: f32 = f32(px_abs.y - px_bounds.y) / f32(px_bounds.h)

	result.x = math.lerp(plot.range_x[0], plot.range_x[1], px_rel_x)
	result.y = math.lerp(plot.range_y[1], plot.range_y[0], px_rel_y) // px is top-down, plot is bottom-up
	return result
}
