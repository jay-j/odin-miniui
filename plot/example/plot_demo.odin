package plot_demo

import plt ".."
import mu "../.."
import ha "../handle"
import "core:fmt"
import "core:log"
import "core:math"
import "core:time"
import gl "vendor:OpenGL"
import SDL "vendor:sdl2"

App :: struct {
	window:                  ^SDL.Window,
	gl_context:              SDL.GLContext,
	t:                       f32, // something handy to have in f32
	time_start:              time.Tick,
	time_frame_start:        time.Tick,
	time_frame_delta_target: time.Duration,
	time_work:               f32,
}

app := App{}

linspace :: proc(low, high: f32, count: int, allocator := context.allocator) -> (res: []f32) {
	assert(high > low)
	res = make([]f32, count)
	dx := (high - low) / f32(count)
	for i in 0 ..< count {
		res[i] = dx * f32(i) + low
	}
	return res
}

main :: proc() {
	context.logger = log.create_console_logger(lowest = .Debug)
	gfx_window_setup(810, 810)
	defer gfx_window_quit()
	app_framerate_control_init()

	// Init from miniui
	gui := mu.init()

	// Generate some sample data for the demo
	x := linspace(-1.5, 2, 1024)
	y := make([]f32, len(x))
	for i in 0 ..< len(x) {
		y[i] = 0.9 * math.sin(4 * x[i])
	}
	th := linspace(0.1, 40, 1e4)
	x2 := make([]f32, len(th))
	y2 := make([]f32, len(th))
	for i in 0 ..< len(th) {
		x2[i] = (th[i] / 50.0 + 0.04 * math.cos(10 * th[i])) * math.cos(th[i])
		y2[i] = (th[i] / 50.0 + 0.04 * math.sin(10 * th[i])) * math.sin(th[i])
	}

	// Do the plotting
	plot_renderer := plt.render_init()

	plot := plt.plot_init(1920, 1080)

	sine := plt.dataset_add(&plot, x[:], y[:], auto_range = true)

	spiral := plt.dataset_add(&plot, x2[:], y2[:], auto_range = true)
	{
		ptr := ha.get_ptr(plot.data, spiral)
		ptr.color = {0.1, 0.8, 0.8, 1.0}
	}

	// Bundle the data used by miniui to display the framebuffer in an image element.
	plot_texture := mu.Texture {
		texture_id = plot.framebuffer_rgb,
		width      = plot.framebuffer_width_max,
		height     = plot.framebuffer_height_max,
		inv_width  = 1.0 / f32(plot.framebuffer_width_max),
		inv_height = 1.0 / f32(plot.framebuffer_height_max),
	}

	log.debugf("Errors before loop start: %v\n", gl.GetError())

	main_loop: for {
		app_framerate_control()

		for event: SDL.Event; SDL.PollEvent(&event); {
			if event.type == SDL.EventType.QUIT {
				break main_loop
			}
			if event.type == SDL.EventType.KEYDOWN {
				#partial switch event.key.keysym.scancode {
				case .ESCAPE:
					break main_loop
				case .NUM1:
					plot.scale_mode = .Stretched
				case .NUM2:
					plot.scale_mode = .Isotropic
				}
			}

			mu.input_sdl_events(&gui.ctx, event)
		}

		// Demo updating data on one of the plots. Choosing here to compute this even if the plot is not shown.
		for i in 0 ..< len(th) {
			x2[i] = (th[i] / 50.0 + 0.04 * math.cos(10 * th[i] + 2 * app.t)) * math.cos(th[i])
			y2[i] = (th[i] / 50.0 + 0.04 * math.sin(10 * th[i] + 1.57 * app.t)) * math.sin(th[i])
		}

		// UI Definition, including drawing the plot. Note that this immediate mode implementation
		// results in the plot-drawing GPU work to only be done if the plot is visible.
		{
			mu.begin(&gui.ctx)
			defer mu.end(&gui.ctx)

			if mu.window(&gui.ctx, "Plot demo", {5, 5, 800, 800}) {
				mu.layout_row(&gui.ctx, {-1}, 0)
				mu.label(&gui.ctx, fmt.tprintf("Frame work time: %.1f ms", app.time_work))

				// Delaying the plot update to here since if the plot isn't visible,
				// the data doesn't need to be sent to the GPU.
				plt.dataset_update(&plot, spiral, x2[:], y2[:])

				// Queue the miniui command first so that the desired framebuffer size
				// is exactly known. Then the framebuffer is updated befor the command
				// queue is executed in mu.draw().
				mu.layout_row(&gui.ctx, {-1}, -1)
				vpw, vph := mu.image_raw(&gui.ctx, plot_texture)
				plt.draw(plot_renderer, &plot, vpw, vph)
			}
		}

		{
			window_width, window_height: i32
			SDL.GetWindowSize(app.window, &window_width, &window_height)
			mu.draw_prepare(gui, window_width, window_height)
		}

		gl.ClearColor(0.5, 0.7, 1.0, 0.0) // TODO what is the right value?
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
		mu.draw(gui, context.temp_allocator)
		SDL.GL_SwapWindow(app.window)

		free_all(context.temp_allocator)
	}
}


gfx_window_setup :: proc(window_width, window_height: i32) {
	// Basic opening of the SDL window and gathering OpenGL
	SDL.Init(SDL.INIT_VIDEO)

	app.window = SDL.CreateWindow(
		"MINIUI PLOTTING EXAMPLE",
		SDL.WINDOWPOS_CENTERED_DISPLAY(1),
		SDL.WINDOWPOS_UNDEFINED,
		window_width,
		window_height,
		SDL.WINDOW_SHOWN | SDL.WINDOW_OPENGL | SDL.WINDOW_RESIZABLE,
	)

	app.gl_context = SDL.GL_CreateContext(app.window)
	SDL.GL_MakeCurrent(app.window, app.gl_context)

	// TODO where do these go?
	SDL.GL_SetAttribute(SDL.GLattr.RED_SIZE, 8)
	SDL.GL_SetAttribute(SDL.GLattr.BLUE_SIZE, 8)
	SDL.GL_SetAttribute(SDL.GLattr.GREEN_SIZE, 8)
	SDL.GL_SetAttribute(SDL.GLattr.ALPHA_SIZE, 8)

	// Framebuffers don't work on OpenGL 3.3
	gl.load_up_to(4, 5, SDL.gl_set_proc_address)

	gl.Enable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.ALPHA_TEST)
}


gfx_window_quit :: proc() {
	SDL.GL_DeleteContext(app.gl_context)
	SDL.DestroyWindow(app.window)
	SDL.Quit()
}


app_framerate_control_init :: proc() {
	app.time_frame_delta_target = 16667 * time.Microsecond
	app.time_start = time.tick_now()
}

app_framerate_control :: proc() {
	now: time.Tick = time.tick_now()
	elapsed := time.tick_diff(app.time_frame_start, now)

	if elapsed < app.time_frame_delta_target {
		time.accurate_sleep(app.time_frame_delta_target - elapsed)
	}

	app.time_frame_start = time.tick_now()
	app.t = cast(f32)time.duration_seconds(time.tick_diff(app.time_frame_start, app.time_start))
	app.time_work = cast(f32)time.duration_milliseconds(elapsed)
}
