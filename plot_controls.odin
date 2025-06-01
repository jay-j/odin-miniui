package miniui

import "core:fmt"
import plt "plot"

plot :: proc(ctx: ^Context, plot: ^plt.Plot, render_cmd := false, opt: Options = {.ALIGN_CENTER}) {
	// TODO all the wrapper stuff
	// show the plot with wrappers for the geometry
	// send mouse interaction
	// right click for mode control popup menu
	opt := opt
	id := get_id(ctx, uintptr(plot))
	r := layout_next(ctx) // TODO  check required?
	update_control(ctx, id, r, opt)

	// TODO: draw_control_frame?

	// BUG: If the size of the container has changed, then it needs to be re-rendered

	// Handle click
	render_cmd := render_cmd
	if ctx.mouse_pressed_bits == {.LEFT} && ctx.focus_id == id {
		fmt.printf("plot was clicked\n")
		center := (plot.range_x[0] + plot.range_x[1]) * 0.5
		radius := 0.5 * (plot.range_x[1] - plot.range_x[0])
		plot.range_x[0] = center - 0.8 * radius
		plot.range_x[1] = center + 0.8 * radius
		render_cmd = true
	}

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
	// vpw, vph := image_raw(ctx, plot_texture)
	src := Rect{0, 0, min(r.w, plot_texture.width), min(r.h, plot_texture.height)}
	draw_image(ctx, plot_texture, r, src, color = {255, 255, 255, 255})

	@(static) render_first := true
	if render_cmd | render_first {
		plt.draw(ctx.plot_renderer, plot, r.w, r.h)
		render_first = false
	}

}
