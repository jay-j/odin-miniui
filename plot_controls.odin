package miniui

import "core:fmt"
import "core:log"
import "core:math"
import "core:strings"
import plt "plot"

plot :: proc(ctx: ^Context, plot: ^plt.Plot, render_cmd := false, opt: Options = {.ALIGN_CENTER}) {
	// show the plot with wrappers for the geometry
	// send mouse interaction
	// right click for mode control popup menu
	label_color := Color{220, 220, 220, 255}
	opt := opt

	// Bundle the titles, axis labels, and plot all in one column
	push_id(ctx, uintptr(plot))
	layout_begin_column(ctx)

	layout := get_layout(ctx)
	plot_with_margins := layout.body

	// Height of the actual pixels that get plotted
	plot_height := plot_with_margins.h - ctx.style.padding - 8 // HACK -3 to prevent scroll bar
	ylabel_width: i32 = 50 // HACK hardcoded

	if plot.title != "" {
		layout_row(ctx, {-1}, ctx.text_height(ctx.style.font))
		rx := layout_next(ctx)
		draw_pos := Vec2{rx.x + rx.w / 2, rx.y}
		draw_pos.x -= ctx.text_width(ctx.style.font, plot.title) / 2
		draw_text(ctx, ctx.style.font, plot.title, draw_pos, label_color)

		plot_height -= ctx.text_height(ctx.style.font)
	}
	if plot.axis_labels.x != "" {
		plot_height -= ctx.text_height(ctx.style.font)
	}
	// Subtract range for x axis numeric labels
	plot_height -= ctx.text_height(ctx.style.font)

	layout_row(ctx, {ylabel_width, -1}, plot_height)

	// HACK Reserve the layout segment for the y-axis labels, but don't draw them yet
	r_ylabel := layout_next(ctx)

	id := ctx.id_stack.items[ctx.id_stack.idx - 1]
	r := layout_next(ctx)
	update_control(ctx, id, r, opt)


	// BUG: If the size of the container has changed, then it needs to be re-rendered

	// TODO shrink the size of the image to leave room for labels and titles and stuff

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

	popup_title := "Plot#Context Menu"
	if .RIGHT in ctx.mouse_released_bits && ctx.hover_id == id {
		mouse_move := ctx.mouse_pos - mouse_start
		if math.abs(mouse_move.x) > MOUSE_DRAG_TOLERANCE || math.abs(mouse_move.y) > MOUSE_DRAG_TOLERANCE {

			drag_start := plot_px_to_coords(plot, r, mouse_start)
			drag_end := plot_px_to_coords(plot, r, ctx.mouse_pos)

			if !plot.scale_auto_x {
				plot.range_x_goal = {min(drag_start[0], drag_end[0]), max(drag_start[0], drag_end[0])}
				plot.animation_timer = plt.PLOT_ZOOM_ANIMATION_RESET
			}
			if !plot.scale_auto_y {
				plot.range_y_goal = {min(drag_start[1], drag_end[1]), max(drag_start[1], drag_end[1])}
				plot.animation_timer = plt.PLOT_ZOOM_ANIMATION_RESET
			}

		} else {
			open_popup(ctx, popup_title)
		}
	}

	if .RIGHT in ctx.mouse_down_bits && ctx.focus_id == id {
		// draw the RMB box zoom
		mouse_move := ctx.mouse_pos - mouse_start
		box := Rect{min(mouse_start.x, ctx.mouse_pos.x), min(mouse_start.y, ctx.mouse_pos.y), abs(mouse_move.x), abs(mouse_move.y)}
		draw_box(ctx, box, Color{200, 128, 200, 255})
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
		plot.animation_timer = 0
	}

	// BUG Cuts off long text length
	if popup(ctx, popup_title) {
		popup_cnt := get_current_container(ctx)
		if .SUBMIT in button(ctx, "reset view") {
			plt.scale_auto_x(plot)
			plt.scale_auto_y(plot)
			popup_cnt.open = false
		}
		// BUG These hold the range but don't trigger new auto-scaling
		checkbox(ctx, "Auto X", &plot.scale_auto_x)
		checkbox(ctx, "Auto Y", &plot.scale_auto_y)
	}


	{ 	// Label the axis limits
		xplus_str := fmt.tprintf(plot.format_str.x, plot.range_x[1])
		xplus_px := plot_coords_to_px(plot, r, {plot.range_x[1], 0})
		if xplus_px.y < r.y {
			xplus_px.y = r.y
		} else if xplus_px.y > r.y + r.h {
			xplus_px.y = r.y + r.h - ctx.text_height(ctx.style.font) - 1
		}
		xplus_px.x -= ctx.text_width(ctx.style.font, xplus_str) + 1
		draw_text(ctx, ctx.style.font, xplus_str, xplus_px, label_color)

		xminus_str := fmt.tprintf(plot.format_str.x, plot.range_x[0])
		xminus_px := plot_coords_to_px(plot, r, {plot.range_x[0], 0})
		if xminus_px.y < r.y {
			xminus_px.y = r.y
		} else if xminus_px.y > r.y + r.h {
			xminus_px.y = r.y + r.h - ctx.text_height(ctx.style.font) - 1
		}
		xminus_px.x += 1
		draw_text(ctx, ctx.style.font, xminus_str, xminus_px, label_color)

		yplus_str := fmt.tprintf(plot.format_str.x, plot.range_y[1])
		yplus_px := plot_coords_to_px(plot, r, {0, plot.range_y[1]})
		if yplus_px.x < r.x {
			yplus_px.x = r.x
		} else if yplus_px.x > r.x + r.w {
			yplus_px.x = r.x + r.w - ctx.text_width(ctx.style.font, yplus_str) - 1
		}
		yplus_px.y += 1
		draw_text(ctx, ctx.style.font, yplus_str, yplus_px, label_color)

		yminus_str := fmt.tprintf(plot.format_str.x, plot.range_y[0])
		yminus_px := plot_coords_to_px(plot, r, {0, plot.range_y[0]})
		if yminus_px.x < r.x {
			yminus_px.x = r.x
		} else if yminus_px.x > r.x + r.w {
			yminus_px.x = r.x + r.w - ctx.text_width(ctx.style.font, yminus_str) - 1
		}
		yminus_px.y -= ctx.text_height(ctx.style.font) - 1
		draw_text(ctx, ctx.style.font, yminus_str, yminus_px, label_color)
	}
	{
		// Draw the coordinates of the mouse cursor location
		if ctx.hover_id == id {
			mouse_pos := plot_px_to_coords(plot, r, ctx.mouse_pos)
			mouse_pos_str := fmt.tprintf(
				strings.concatenate({"(", plot.format_str[0], ", ", plot.format_str[1], ")"}, context.temp_allocator),
				mouse_pos.x,
				mouse_pos.y,
			)
			draw_pos := ctx.mouse_pos + {0, -ctx.text_height(ctx.style.font)}

			draw_text(ctx, ctx.style.font, mouse_pos_str, draw_pos, label_color)
		}
	}
	{
		{ 	// Draw the Y-axis numeric labels
			for val in plot.grid_y {
				if math.is_nan(val) {break} 	// HACK Use better small dynamic arrays once available
				txt := fmt.tprintf(plot.format_str.y, val)
				draw_pos := plot_coords_to_px(plot, r, {0, val})
				if draw_pos.y < r_ylabel.y {continue}
				if draw_pos.y + ctx.text_height(ctx.style.font) > r_ylabel.y + r_ylabel.h {continue}
				draw_pos.y -= ctx.text_height(ctx.style.font) / 2
				draw_pos.x = r_ylabel.x + r_ylabel.w // TODO offsets
				draw_pos.x -= ctx.text_width(ctx.style.font, txt)

				draw_text(ctx, ctx.style.font, txt, draw_pos, label_color)
			}

		}
		{ 	// Draw the X-axis numeric labels
			layout_row(ctx, {-1}, ctx.text_height(ctx.style.font))
			rx := layout_next(ctx)

			for val in plot.grid_x {
				if math.is_nan(val) {break} 	// HACK Use better small dynamic arrays once available
				txt := fmt.tprintf(plot.format_str.x, val)
				draw_pos := plot_coords_to_px(plot, r, {val, 0})
				draw_pos.y = rx.y
				if draw_pos.x < r.x {continue} 	// HACK using r.x instead of rx.x hints that maybe it's better to change the layout
				if draw_pos.x > rx.x + rx.w {continue}

				draw_pos.x -= ctx.text_width(ctx.style.font, txt) / 2

				draw_text(ctx, ctx.style.font, txt, draw_pos, label_color)
			}
		}

		// Draw some kind of axis labels
		// BUG will this be outside the clip limits?
		if plot.axis_labels.x != "" {
			layout_row(ctx, {-1}, ctx.text_height(ctx.style.font))
			rx := layout_next(ctx)
			draw_pos := Vec2{rx.x + rx.w / 2, rx.y}
			draw_pos.x -= ctx.text_width(ctx.style.font, plot.axis_labels.x) / 2

			draw_text(ctx, ctx.style.font, plot.axis_labels.x, draw_pos, label_color)
		}
	}
	layout_end_column(ctx)
	pop_id(ctx)

}


// Convert a window-space set of pixels to coordinates within the plot.
plot_px_to_coords :: proc(plot: ^plt.Plot, px_bounds: Rect, px_abs: Vec2) -> (result: [2]f32) {
	plot_validate_bounds(plot, px_bounds)

	px_rel_x: f32 = f32(px_abs.x - px_bounds.x) / f32(px_bounds.w)
	px_rel_y: f32 = f32(px_abs.y - px_bounds.y) / f32(px_bounds.h)

	result.x = math.lerp(plot.range_x[0], plot.range_x[1], px_rel_x)
	result.y = math.lerp(plot.range_y[1], plot.range_y[0], px_rel_y) // px is top-down, plot is bottom-up
	return result
}


// Convert coordinates within the plot to window-space pixels.
plot_coords_to_px :: proc(plot: ^plt.Plot, px_bounds: Rect, pos: [2]f32) -> (result: Vec2) {
	plot_validate_bounds(plot, px_bounds)

	pos_rel_x := (pos.x - plot.range_x[0]) / (plot.range_x[1] - plot.range_x[0])
	pos_rel_y := (pos.y - plot.range_y[0]) / (plot.range_y[1] - plot.range_y[0])

	result.x = i32(math.lerp(f32(px_bounds.x), f32(px_bounds.x + px_bounds.w), pos_rel_x))
	result.y = i32(math.lerp(f32(px_bounds.y + px_bounds.h), f32(px_bounds.y), pos_rel_y))
	return
}


@(private)
plot_validate_bounds :: proc(plot: ^plt.Plot, px_bounds: Rect) {
	if px_bounds.w > plot.framebuffer_width_max {
		log.warnf(
			"Plot %p display width (%v) greater size than framebuffer width (%v), px->coords will be inaccurate.",
			plot,
			px_bounds.w,
			plot.framebuffer_width_max,
		)
	}
	if px_bounds.h > plot.framebuffer_height_max {
		log.warnf(
			"Plot %p display height (%v) greater size than framebuffer height (%v), px->coords will be inaccurate.",
			plot,
			px_bounds.h,
			plot.framebuffer_height_max,
		)
	}
}
