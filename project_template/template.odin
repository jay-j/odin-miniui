package my_project
import mu ".."
import gl "vendor:OpenGL"
import SDL "vendor:sdl2"

app: mu.App

main :: proc() {
	SDL.Init(SDL.INIT_VIDEO)

	app.window = SDL.CreateWindow(
		"my applicataion",
		SDL.WINDOWPOS_CENTERED_DISPLAY(1),
		SDL.WINDOWPOS_UNDEFINED,
		1920,
		1080,
		SDL.WINDOW_SHOWN | SDL.WINDOW_OPENGL | SDL.WINDOW_RESIZABLE,
	)
	mu.app_window_setup(&app)
	gui := mu.init(plot = true)

	main_loop: for {

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

		gl.ClearColor(0.5, 0.7, 1.0, 0.0)
		gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

		{ 	// UI here
			mu.begin(&gui.ctx)
			defer mu.end(&gui.ctx)
			if mu.window(&gui.ctx, "window 1", {0, 0, 200, 400}) {
				mu.layout_row(&gui.ctx, {-1})
				mu.label(&gui.ctx, "hello world")
			}
		}


		mu.app_display(&app, gui)
		free_all(context.temp_allocator)
	}
}
