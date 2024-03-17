package miniui_example

// Example!

import mu ".."
import "core:fmt"
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
}

app := App{}


main :: proc() {
	gfx_window_setup(1200, 800)
	defer gfx_window_quit()
	app_framerate_control_init()

	// Init from miniui
	gui := mu.init()

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
				}
			}

			mu.input_sdl_events(&gui.ctx, event)

		}

		gl.ClearColor(0.5, 0.7, 1.0, 0.0) // TODO what is the right value?
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		{
			mu.begin(&gui.ctx)
			// defer mu.end(&gui.ctx) // NOTE: must mu.end() before calling rendering


			if mu.window(&gui.ctx, "test window", {0, 0, 200, 400}) {
				mu.label(&gui.ctx, "hello world")

				if .SUBMIT in mu.button(&gui.ctx, "dis a button", icon = .CHECK) {
					fmt.printf("button was pressed\n")
				}

				@(static)
				check: bool = false
				mu.checkbox(&gui.ctx, "here a checkbox", &check)
				if check {
					mu.label(&gui.ctx, "true")
				}

				@(static)
				number: f32 = 3
				mu.number(&gui.ctx, &number, 0.5, "%.2f")

				@(static)
				number2: f32 = 11
				// id := mu.get_id(&gui.ctx, uintptr(number2)) // ? todo these are kind of annoying out here?
				// base := mu.layout_next(&gui.ctx) // ??
				// mu.number_textbox(&gui.ctx, &number2, base, id, "%.3f")

				mu.slider(&gui.ctx, &number2, -20, 20, 0.5, "%.1f")

			}

			mu.end(&gui.ctx) 
		}

		mu.draw_prepare(gui, 1200, 800)
		mu.draw(gui, context.temp_allocator)
		SDL.GL_SwapWindow(app.window)

		free_all(context.temp_allocator)

	}

}


gfx_window_setup :: proc(window_width, window_height: i32) {
	// Basic opening of the SDL window and gathering OpenGL
	SDL.Init(SDL.INIT_VIDEO)

 	app.window = SDL.CreateWindow(
		"MINIUI EXAMPLE",
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

	gl.load_up_to(3, 3, SDL.gl_set_proc_address)

	// Disabling the OpenGL Depth Test greatly enables seemingly good alpha over behavior
	// gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.ALPHA_TEST)

	// TODO consider rendering all opaque tinted things before transparent tinted things
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
}
