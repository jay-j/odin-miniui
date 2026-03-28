package miniui

import "core:fmt"
import "core:log"
import "core:math"
import "core:strings"
import "core:time"
import plt "plot"
import ha "plot/handle"

plot :: proc(ctx: ^Context, plot: ^plt.Plot, opt: Options = {.ALIGN_CENTER}) {
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
	// BUG actually draw the text for the y axis descriptive label
	r_ylabel := layout_next(ctx)

	id := ctx.id_stack.items[ctx.id_stack.idx - 1]
	r := layout_next(ctx)
	update_control(ctx, id, r, opt)


	plot_texture := Texture {
		texture_id = plot.fb.rgb,
		width      = plot.fb.width_max,
		height     = plot.fb.height_max,
		inv_width  = 1.0 / f32(plot.fb.width_max),
		inv_height = 1.0 / f32(plot.fb.height_max),
	}

	// Queue the miniui command first so that the desired framebuffer size
	// is exactly known. Then the framebuffer is updated before the command
	// queue is executed in mu.draw().
	src := Rect{0, 0, min(r.w, plot_texture.width), min(r.h, plot_texture.height)}
	draw_image(ctx, plot_texture, r, src, color = {255, 255, 255, 255})

	plt.draw(ctx.plot_renderer, plot, r.w, r.h)

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
		plot.fb.cached = false
	}

	// WARNING: Since containers don't automatically expand to fit their content,
	// long labels will get cutoff unless the popup is manually expanded.
	if popup(ctx, popup_title) {
		layout_row(ctx, {100})
		popup_cnt := get_current_container(ctx)
		if .SUBMIT in button(ctx, "reset view") {
			plt.scale_auto_x(plot)
			plt.scale_auto_y(plot)
			popup_cnt.open = false
		}
		if .CHANGE in checkbox(ctx, "Auto X", &plot.scale_auto_x) {
			if plot.scale_auto_x {plt.scale_auto_x(plot)}
		}
		if .CHANGE in checkbox(ctx, "Auto Y", &plot.scale_auto_y) {
			if plot.scale_auto_y {plt.scale_auto_y(plot)}
		}
		enum_selector(ctx, &plot.legend_corner)
	}

	{ 	// Zoom on scroll wheel around the screen center
		if ctx.scroll_delta.y != 0 && ctx.hover_id == id {
			scale := 1.0 + 0.01 * f32(ctx.scroll_delta.y)
			plot.animation_timer = plt.PLOT_ZOOM_ANIMATION_RESET

			center_x := 0.5 * (plot.range_x[0] + plot.range_x[1])
			radius_x := 0.5 * (plot.range_x[1] - plot.range_x[0])
			plot.range_x_goal = center_x + scale * [2]f32{-radius_x, radius_x}

			center_y := 0.5 * (plot.range_y[0] + plot.range_y[1])
			radius_y := 0.5 * (plot.range_y[1] - plot.range_y[0])
			plot.range_y_goal = center_y + scale * [2]f32{-radius_y, radius_y}
		}
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
	plot_draw_legend(ctx, plot, r)
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
	if px_bounds.w > plot.fb.width_max {
		log.warnf(
			"Plot %p display width (%v) greater size than framebuffer width (%v), px->coords will be inaccurate.",
			plot,
			px_bounds.w,
			plot.fb.width_max,
		)
	}
	if px_bounds.h > plot.fb.height_max {
		log.warnf(
			"Plot %p display height (%v) greater size than framebuffer height (%v), px->coords will be inaccurate.",
			plot,
			px_bounds.h,
			plot.fb.height_max,
		)
	}
}


// Draw the legend within the specified rectangle.
plot_draw_legend :: proc(ctx: ^Context, plot: ^plt.Plot, r_given: Rect) {
	if plot.legend_hidden {return}
	push_id(ctx, uintptr(&plot.fb_legend))
	defer pop_id(ctx)

	// Calculate dimensions
	r := r_given

	LEGEND_PADDING :: 2
	LEGEND_GRAPHIC_WIDTH :: 40
	legend_text_width: i32 = 0
	legend_label_quantity: i32 = 0
	{
		// PERFORMANCE: A redudant loop through the datasets, and redundant measurement of text width
		dset_iterator := ha.make_iter(plot.data)
		for dset in ha.iter_ptr(&dset_iterator) {
			if dset.label == "" {continue}
			px := ctx.text_width(ctx.style.font, dset.label)
			legend_text_width = max(legend_text_width, px)
			legend_label_quantity += 1
		}
	}

	// Calculate the required height based on the quantity of datasets.
	height_per_label := ctx.text_height(ctx.style.font) + ctx.style.spacing
	r.h = legend_label_quantity * height_per_label + 2 * LEGEND_PADDING
	r.w = LEGEND_GRAPHIC_WIDTH + legend_text_width + ctx.style.padding

	// If legend covers too much of the figure then don't show it.
	if r.h * r.w * 2 > r_given.h * r_given.w {
		return
	}

	// ASSUME: The incoming coordinates of r_given are for .NORTHWEST
	switch plot.legend_corner {
	case .Northwest:
	case .Northeast:
		r.x = r_given.x + r_given.w - r.w
	case .Southeast:
		r.x = r_given.x + r_given.w - r.w
		r.y = r_given.y + r_given.h - r.h
	case .Southwest:
		r.y = r_given.y + r_given.h - r.h
	}

	// NOTE: The plot is rendered with an alpha background, this color gives it a background.
	color_background := Color{u8(plot.color_background.r * 255), u8(plot.color_background.g * 255), u8(plot.color_background.b * 255), 255}
	draw_rect(ctx, r, color_background)

	legend_texture := Texture {
		texture_id = plot.fb_legend.rgb,
		width      = plot.fb_legend.width_max,
		height     = plot.fb_legend.height_max,
		inv_width  = 1.0 / f32(plot.fb_legend.width_max),
		inv_height = 1.0 / f32(plot.fb_legend.height_max),
	}

	legend_rect := Rect{r.x, r.y, LEGEND_GRAPHIC_WIDTH, r.h}
	legend_rect = expand_rect(legend_rect, -LEGEND_PADDING)

	src := Rect{0, 0, min(legend_rect.w, legend_texture.width), min(legend_rect.h, legend_texture.height)}
	draw_image(ctx, legend_texture, legend_rect, src, color = {255, 255, 255, 255})
	// TODO interaction with the legend to highlight specific datasets on mouseover?

	// TODO add in render caching info
	plt.draw_legend(ctx.plot_renderer, plot, legend_rect.w, legend_rect.h, height_per_label)

	y: i32 = 2 * LEGEND_PADDING
	dest_iterator := ha.make_iter(plot.data)
	for dset in ha.iter_ptr(&dest_iterator) {
		if dset.label == "" {continue}
		draw_text(ctx, ctx.style.font, dset.label, {r.x + LEGEND_GRAPHIC_WIDTH + LEGEND_PADDING, r.y + y}, ctx.style.colors[.TEXT])
		y += height_per_label
	}
}
