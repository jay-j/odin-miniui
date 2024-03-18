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
			defer mu.end(&gui.ctx)

			if mu.window(&gui.ctx, "test window", {0, 0, 200, 400}) {
				@(static)
				check_early: bool = false
				mu.checkbox(&gui.ctx, "checkbox_early", &check_early)

				mu.label(&gui.ctx, "hello world")

				if .SUBMIT in mu.button(&gui.ctx, "", icon = .CHECK) {
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
				mu.slider(&gui.ctx, &number2, -20, 20, 0.5, "%.1f")

				@(static)
				check_end: bool = false
				mu.checkbox(&gui.ctx, "checkbox_END", &check_end)
			}

			all_windows(&gui.ctx)

		}

		{
			window_width, window_height: i32
			SDL.GetWindowSize(app.window, &window_width, &window_height)
			mu.draw_prepare(gui, window_width, window_height)
		}

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

//////////////////////////////////////////////////////////////////////////////////////////
// Example from GB!

state := struct {
	mu_ctx:          mu.Context,
	log_buf:         [1 << 16]byte,
	log_buf_len:     int,
	log_buf_updated: bool,
	bg:              mu.Color,
	atlas_texture:   ^SDL.Texture,
} {
	bg = {90, 95, 100, 255},
}


u8_slider :: proc(ctx: ^mu.Context, val: ^u8, lo, hi: u8) -> (res: mu.Result_Set) {
	mu.push_id(ctx, uintptr(val))

	@(static)
	tmp: mu.Real
	tmp = mu.Real(val^)
	res = mu.slider(ctx, &tmp, mu.Real(lo), mu.Real(hi), 0, "%.0f", {.ALIGN_CENTER})
	val^ = u8(tmp)
	mu.pop_id(ctx)
	return
}

write_log :: proc(str: string) {
	state.log_buf_len += copy(state.log_buf[state.log_buf_len:], str)
	state.log_buf_len += copy(state.log_buf[state.log_buf_len:], "\n")
	state.log_buf_updated = true
}

read_log :: proc() -> string {
	return string(state.log_buf[:state.log_buf_len])
}
reset_log :: proc() {
	state.log_buf_updated = true
	state.log_buf_len = 0
}


all_windows :: proc(ctx: ^mu.Context) {
	@(static)
	opts := mu.Options{.NO_CLOSE}

	if mu.window(ctx, "Demo Window", {40, 40, 300, 450}, opts) {
		if .ACTIVE in mu.header(ctx, "Window Info") {
			win := mu.get_current_container(ctx)
			mu.layout_row(ctx, {54, -1}, 0)
			mu.label(ctx, "Position:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.x, win.rect.y))
			mu.label(ctx, "Size:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.w, win.rect.h))
		}

		if .ACTIVE in mu.header(ctx, "Window Options") {
			mu.layout_row(ctx, {120, 120, 120}, 0)
			for opt in mu.Opt {
				state := opt in opts
				if .CHANGE in mu.checkbox(ctx, fmt.tprintf("%v", opt), &state) {
					if state {
						opts += {opt}
					} else {
						opts -= {opt}
					}
				}
			}
		}

		if .ACTIVE in mu.header(ctx, "Test Buttons", {.EXPANDED}) {
			mu.layout_row(ctx, {86, -110, -1})
			mu.label(ctx, "Test buttons 1:")
			if .SUBMIT in mu.button(ctx, "Button 1") {write_log("Pressed button 1")}
			if .SUBMIT in mu.button(ctx, "Button 2") {write_log("Pressed button 2")}
			mu.label(ctx, "Test buttons 2:")
			if .SUBMIT in mu.button(ctx, "Button 3") {write_log("Pressed button 3")}
			if .SUBMIT in mu.button(ctx, "Button 4") {write_log("Pressed button 4")}
		}

		if .ACTIVE in mu.header(ctx, "Tree and Text", {.EXPANDED}) {
			mu.layout_row(ctx, {140, -1})
			mu.layout_begin_column(ctx)
			if .ACTIVE in mu.treenode(ctx, "Test 1") {
				if .ACTIVE in mu.treenode(ctx, "Test 1a") {
					mu.label(ctx, "Hello")
					mu.label(ctx, "world")
				}
				if .ACTIVE in mu.treenode(ctx, "Test 1b") {
					if .SUBMIT in mu.button(ctx, "Button 1") {write_log("Pressed button 1")}
					if .SUBMIT in mu.button(ctx, "Button 2") {write_log("Pressed button 2")}
				}
			}
			if .ACTIVE in mu.treenode(ctx, "Test 2") {
				mu.layout_row(ctx, {53, 53})
				if .SUBMIT in mu.button(ctx, "Button 3") {write_log("Pressed button 3")}
				if .SUBMIT in mu.button(ctx, "Button 4") {write_log("Pressed button 4")}
				if .SUBMIT in mu.button(ctx, "Button 5") {write_log("Pressed button 5")}
				if .SUBMIT in mu.button(ctx, "Button 6") {write_log("Pressed button 6")}
			}
			if .ACTIVE in mu.treenode(ctx, "Test 3") {
				@(static)
				checks := [3]bool{true, false, true}
				mu.checkbox(ctx, "Checkbox 1", &checks[0])
				mu.checkbox(ctx, "Checkbox 2", &checks[1])
				mu.checkbox(ctx, "Checkbox 3", &checks[2])

			}
			mu.layout_end_column(ctx)

			mu.layout_begin_column(ctx)
			mu.layout_row(ctx, {-1})
			mu.text(
				ctx,
				"Lorem ipsum dolor sit amet, consectetur adipiscing " +
				"elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus " +
				"ipsum, eu varius magna felis a nulla.",
			)
			mu.layout_end_column(ctx)
		}

		if .ACTIVE in mu.header(ctx, "Background Colour", {.EXPANDED}) {
			mu.layout_row(ctx, {-78, -1}, 68)
			mu.layout_begin_column(ctx)
			{
				mu.layout_row(ctx, {46, -1}, 0)
				mu.label(ctx, "Red:");u8_slider(ctx, &state.bg.r, 0, 255)
				mu.label(ctx, "Green:");u8_slider(ctx, &state.bg.g, 0, 255)
				mu.label(ctx, "Blue:");u8_slider(ctx, &state.bg.b, 0, 255)
			}
			mu.layout_end_column(ctx)

			r := mu.layout_next(ctx)
			mu.draw_rect(ctx, r, state.bg)
			mu.draw_box(ctx, mu.expand_rect(r, 1), ctx.style.colors[.BORDER])
			mu.draw_control_text(
				ctx,
				fmt.tprintf("#%02x%02x%02x", state.bg.r, state.bg.g, state.bg.b),
				r,
				.TEXT,
				{.ALIGN_CENTER},
			)
		}
	}

	if mu.window(ctx, "Log Window", {350, 40, 300, 200}, opts) {
		mu.layout_row(ctx, {-1}, -28)
		mu.begin_panel(ctx, "Log")
		mu.layout_row(ctx, {-1}, -1)
		mu.text(ctx, read_log())
		if state.log_buf_updated {
			panel := mu.get_current_container(ctx)
			panel.scroll.y = panel.content_size.y
			state.log_buf_updated = false
		}
		mu.end_panel(ctx)

		@(static)
		buf: [128]byte
		@(static)
		buf_len: int
		submitted := false
		mu.layout_row(ctx, {-70, -1})
		if .SUBMIT in mu.textbox(ctx, buf[:], &buf_len) {
			mu.set_focus(ctx, ctx.last_id)
			submitted = true
		}
		if .SUBMIT in mu.button(ctx, "Submit") {
			submitted = true
		}
		if submitted {
			write_log(string(buf[:buf_len]))
			buf_len = 0
		}
	}

	if mu.window(ctx, "Style Window", {350, 250, 300, 240}) {
		@(static)
		colors := [mu.Color_Type]string {
			.TEXT         = "text",
			.BORDER       = "border",
			.WINDOW_BG    = "window bg",
			.TITLE_BG     = "title bg",
			.TITLE_TEXT   = "title text",
			.PANEL_BG     = "panel bg",
			.BUTTON       = "button",
			.BUTTON_HOVER = "button hover",
			.BUTTON_FOCUS = "button focus",
			.BASE         = "base",
			.BASE_HOVER   = "base hover",
			.BASE_FOCUS   = "base focus",
			.SCROLL_BASE  = "scroll base",
			.SCROLL_THUMB = "scroll thumb",
		}

		sw := i32(f32(mu.get_current_container(ctx).body.w) * 0.14)
		mu.layout_row(ctx, {80, sw, sw, sw, sw, -1})
		for label, col in colors {
			mu.label(ctx, label)
			u8_slider(ctx, &ctx.style.colors[col].r, 0, 255)
			u8_slider(ctx, &ctx.style.colors[col].g, 0, 255)
			u8_slider(ctx, &ctx.style.colors[col].b, 0, 255)
			u8_slider(ctx, &ctx.style.colors[col].a, 0, 255)
			mu.draw_rect(ctx, mu.layout_next(ctx), ctx.style.colors[col])
		}
	}

}
