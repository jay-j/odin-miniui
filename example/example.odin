package miniui_example

// Example!

import mu ".."
import "core:fmt"
import glm "core:math/linalg/glsl"
import "core:time"
import gl "vendor:OpenGL"
import SDL "vendor:sdl2"

import "core:math"
import "core:strings"
import stbi "vendor:stb/image"

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

	tex_demo: mu.Texture = setup_texture("texture_demo.png")

	vp := viewport_init()

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
				mu.layout_row(&gui.ctx, {-1}, 0)
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

			if mu.window(&gui.ctx, "image here", {700, 200, 300, 300}) {
				mu.layout_row(&gui.ctx, {-1}, 0)
				mu.label(&gui.ctx, "image below here: make the text really long")
				mu.layout_row(&gui.ctx, {-1}, 128)
				mu.image(
					&gui.ctx,
					tex_demo,
					mu.Rect{0, 0, tex_demo.width, tex_demo.height},
					mu.Rect{0, 0, 256, 256},
				)
				mu.layout_row(&gui.ctx, {-1}, 0)
				mu.label(&gui.ctx, "image above here. again want long text example")
			}

			all_windows(&gui.ctx)

		}

		{
			window_width, window_height: i32
			SDL.GetWindowSize(app.window, &window_width, &window_height)
			mu.draw_prepare(gui, window_width, window_height)
		}

		mu.draw(gui, context.temp_allocator)

		viewport_draw(&vp)

		SDL.GL_SwapWindow(app.window)

		free_all(context.temp_allocator)
	}
}

setup_texture :: proc(filename: string, allocator := context.allocator) -> (tex: mu.Texture) {
	context.allocator = allocator

	texture_raw_channels: i32
	texture_raw: [^]u8 = stbi.load(
		strings.clone_to_cstring(filename, allocator = context.temp_allocator),
		&tex.width,
		&tex.height,
		&texture_raw_channels,
		4,
	)
	if texture_raw == nil {
		// TODO better error handling
		assert(false)
	}
	fmt.printf(
		"Loaded image from %v is %v x %v with %v channels\n",
		filename,
		tex.width,
		tex.height,
		texture_raw_channels,
	)

	tex.inv_width = 1.0 / f32(tex.width)
	tex.inv_height = 1.0 / f32(tex.height)

	// Get the texture pushed to the GPU
	gl.GenTextures(1, &tex.texture_id)
	gl.BindTexture(gl.TEXTURE_2D, tex.texture_id)

	gl.TexImage2D(
		target = gl.TEXTURE_2D,
		level = 0,
		internalformat = gl.RGBA,
		width = tex.width,
		height = tex.height,
		border = 0,
		format = gl.RGBA,
		type = gl.UNSIGNED_BYTE,
		pixels = rawptr(texture_raw),
	)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.BindTexture(gl.TEXTURE_2D, 0)

	return
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

//////////////////////////////////////////////////////////////////////////////////////////
// 

Viewport :: struct {
	shader: mu.Shader,
	// vertices
	// indices
	framebuffer_id: u32,
	framebuffer_texture_id: u32,
	framebuffer_depth_id: u32,
}

Viewport_Vertex :: struct #packed {
	// 28 bytes
	pos:   glm.vec3,
	color: glm.vec4,
}

Viewport_Line :: struct #packed {
	// 56 bytes
	vert: [2]Viewport_Vertex,
}

viewport_init :: proc() -> (vp: Viewport) {
	program_ok: bool

	// A simple line drawing shader
	vp.shader.program, program_ok = gl.load_shaders_source(shader_lines_vertex, shader_lines_frag)
	if !program_ok {
		panic("Failed to create GLSL program for demo line rendering.")
	}
	gl.UseProgram(vp.shader.program)

	gl.GenVertexArrays(1, &vp.shader.vao)
	gl.BindVertexArray(vp.shader.vao)

	gl.GenBuffers(1, &vp.shader.vbo)

	vp.shader.uniforms = gl.get_uniforms_from_program(vp.shader.program)
	fmt.printf("Uniforms are: %#v\n", vp.shader.uniforms)

	fmt.printf("Size of Viewport_Vertex: %v bytes\n", size_of(Viewport_Vertex))

	return
}


viewport_draw_prepare :: proc(vp: ^Viewport) {
	// glBindFramebuffer(GL_FRAMEBUFFER, vp->framebuffer_id);

	gl.UseProgram(0)

	// TODO this should not be a sissor anymore once a framebuffer is used!
	gl.Viewport(0, 0, 512, 512) // TODO hardcoded
	{
		gl.Enable(gl.SCISSOR_TEST)
		gl.Scissor(0, 0, 512, 512)
	}

	gl.ClearColor(0, 0, 0, 0)
	gl.Clear(gl.COLOR_BUFFER_BIT)
	gl.Clear(gl.DEPTH_BUFFER_BIT)

	gl.Disable(gl.SCISSOR_TEST)

	gl.UseProgram(vp.shader.program)
	gl.BindVertexArray(vp.shader.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, vp.shader.vbo)

	// set the vertex attribute stuff
	gl.EnableVertexAttribArray(0) // pos
	gl.EnableVertexAttribArray(1) // color in

	gl.VertexAttribPointer(
		0,
		3,
		gl.FLOAT,
		false,
		size_of(Viewport_Vertex),
		offset_of(Viewport_Vertex, pos),
	) // within the buffer where is position?
	gl.VertexAttribPointer(
		1,
		4,
		gl.FLOAT,
		false,
		size_of(Viewport_Vertex),
		offset_of(Viewport_Vertex, color),
	) // where is color? stride?
}


viewport_draw :: proc(vp: ^Viewport) {
	viewport_draw_prepare(vp)

	// context.temp_allocator is assumed to be cleared once per frame (no leak here)
	lineset := make([dynamic]Viewport_Line, 0, 128, context.temp_allocator)

	// Draw the stuff in between
	line :: proc(v1, v2: glm.vec3) -> (res: Viewport_Line) {
		res.vert[0].pos = v1
		res.vert[1].pos = v2
		res.vert[0].color = {0.8, 0.5, 0.5, 1.0}
		res.vert[1].color = {0.5, 0.5, 0.8, 1.0}
		return
	}
	append(&lineset, line({0, 0, 0.1}, {0.9, 0.9, 0.9}))
	append(&lineset, line({0, 0, 0.1}, {-0.5, -0.1, 0.2}))
	append(&lineset, line({0.1, 0.2, .3}, {-0.2, 0.2, 0.5}))

	viewport_draw_flush(vp, &lineset)
}


viewport_draw_flush :: proc(vp: ^Viewport, lineset: ^[dynamic]Viewport_Line) {

	tf := glm.mat4{1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, -1.0, 0, 0, 0, 0, 1} // 

	proj := glm.mat4Ortho3d(-1, 1, -1, 1, 0.1, 20) // half widths, half heights, near, far
	view := glm.mat4LookAt({0, 0.3 * math.sin(app.t), 2}, {0, 0, 0}, {0, 1, 0}) // eye location, what to look at, up vector
	u_transform := proj * view * tf
	gl.UniformMatrix4fv(vp.shader.uniforms["MVP"].location, 1, false, &u_transform[0, 0])

	// Push data to the GPU and call draw!
	bytes_to_push := len(lineset) * size_of(lineset[0])
	lines_to_draw := i32(2 * len(lineset))
	gl.BufferData(gl.ARRAY_BUFFER, bytes_to_push, raw_data(lineset[:]), gl.DYNAMIC_DRAW)
	gl.DrawArrays(gl.LINES, 0, lines_to_draw)
}


shader_lines_vertex: string = `
#version 330 core
layout(location=0) in vec3 position; // model space
layout(location=1) in vec4 color_in;

uniform mat4 MVP;
out vec4 color;

void main(){
	gl_Position = MVP * vec4(position, 1);
	// gl_Position = vec4(position, 1);
	color = color_in;
}
`

shader_lines_frag: string = `
#version 330 core
in vec4 color;
out vec4 color_out;

void main(){
    color_out = color;
}
`
