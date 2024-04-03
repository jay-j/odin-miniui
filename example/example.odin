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

	vp := viewport_init(1920, 1080) // TODO hardcoded. Maximum screen dimensions
	vp_texture := mu.Texture {
		texture_id = vp.framebuffer_texture_id,
		// TODO need these to be non insane and constant things! link between render calls and this!
		width      = 1920,
		height     = 1080,
		inv_width  = 1.0 / 1920,
		inv_height = 1.0 / 1080,
	}

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

			if mu.window(&gui.ctx, "image here", {760, 200, 300, 300}) {
				mu.layout_row(&gui.ctx, {-1}, 0)
				mu.label(&gui.ctx, "image below here: make the text really long")
				mu.layout_row(&gui.ctx, {-1}, 128)
				mu.image_scaled(&gui.ctx, tex_demo)
				mu.layout_row(&gui.ctx, {-1}, 0)
				mu.label(&gui.ctx, "image above here. again want long text example")
			}

			all_windows(&gui.ctx)

			{
				win: ^mu.Container
				vpw, vph: i32

				// A primary viewport display! Queueing the image draw command first allows the
				// framebuffer to be rendered at the exact required output resolution.
				if mu.window(&gui.ctx, "Framebuffer demo", {50, 100, 512, 512}) {
					mu.layout_row(&gui.ctx, {-1}, 0)
					mu.label(&gui.ctx, "Hello this should be above the image")

					mu.layout_row(&gui.ctx, {-1}, -1)
					vpw, vph = mu.image_raw(&gui.ctx, vp_texture)
					viewport_draw(&vp, vpw, vph)
				}

				// Secondary displays of the framebuffer texture (e.g. minimap)
				if mu.window(&gui.ctx, "framebuffer mini window", {450, 100, 300, 300}) {
					mu.layout_row(&gui.ctx, {-1}, 0)
					mu.label(&gui.ctx, "label above the small framebuffer")

					// This slot is too wide for the image
					mu.layout_row(&gui.ctx, {-1}, 128)
					mu.image_scaled(&gui.ctx, vp_texture, src = mu.Rect{w = vpw, h = vph})
					mu.layout_row(&gui.ctx, {-1})
					mu.label(&gui.ctx, "framebuffer above this?")

					// This slot is too narrow for the image
					mu.layout_row(&gui.ctx, {32, 32, -1}, 200)
					mu.label(&gui.ctx, "left")
					mu.image_scaled(&gui.ctx, vp_texture, src = mu.Rect{w = vpw, h = vph})
					mu.label(&gui.ctx, "right")
					mu.layout_row(&gui.ctx, {-1})
					mu.label(&gui.ctx, "bottom")
				}
			}
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
	fmt.printf("Loaded image from %v is %v x %v with %v channels\n", filename, tex.width, tex.height, texture_raw_channels)

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

	// Framebuffers don't work on OpenGL 3.3
	gl.load_up_to(4, 5, SDL.gl_set_proc_address)

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
// A more interesting example of arbitrary rendering to a framebuffer, then have miniui display
// that framebuffer as an image.

Viewport :: struct {
	shader:                 mu.Shader,

	// Representation used for framebuffer definition
	framebuffer_id:         u32,
	framebuffer_texture_id: u32,
	framebuffer_depth_id:   u32,
	framebuffer_width_max:  i32,
	framebuffer_height_max: i32,

	// Representation of the texture used for rendering
	texture:                mu.Texture,
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

viewport_init :: proc(width, height: i32) -> (vp: Viewport) {
	program_ok: bool

	{
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
	}

	{
		// Setup the framebuffer
		gl.CreateFramebuffers(1, &vp.framebuffer_id)
		vp.framebuffer_width_max = width
		vp.framebuffer_height_max = height

		// Color texture
		gl.CreateTextures(gl.TEXTURE_2D, 1, &vp.framebuffer_texture_id)
		gl.TextureParameteri(vp.framebuffer_texture_id, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
		gl.TextureParameteri(vp.framebuffer_texture_id, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
		gl.TextureParameteri(vp.framebuffer_texture_id, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
		gl.TextureParameteri(vp.framebuffer_texture_id, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
		gl.TextureParameteri(vp.framebuffer_texture_id, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

		gl.TextureStorage2D(vp.framebuffer_texture_id, 1, gl.RGBA8, vp.framebuffer_width_max, vp.framebuffer_height_max)
		gl.NamedFramebufferTexture(vp.framebuffer_id, gl.COLOR_ATTACHMENT0, vp.framebuffer_texture_id, 0)

		// Depth texture
		gl.CreateTextures(gl.TEXTURE_2D, 1, &vp.framebuffer_depth_id)
		gl.TextureStorage2D(vp.framebuffer_depth_id, 1, gl.DEPTH24_STENCIL8, vp.framebuffer_width_max, vp.framebuffer_height_max)
		gl.NamedFramebufferTexture(vp.framebuffer_id, gl.DEPTH_STENCIL_ATTACHMENT, vp.framebuffer_depth_id, 0)
	}

	{
		// Setup the ui texture for displaying
		vp.texture = mu.Texture {
			texture_id = vp.framebuffer_texture_id,
			width      = width,
			inv_width  = 1.0 / f32(width),
			height     = height,
			inv_height = 1.0 / f32(height),
		}
	}

	return
}


// Activate shader & uniforms; likely to be done only once even if multiple GPU draw calls are actually used
viewport_draw_prepare :: proc(vp: ^Viewport, width, height: i32) {
	gl.UseProgram(0)

	gl.UseProgram(vp.shader.program)
	gl.BindVertexArray(vp.shader.vao)
	gl.BindBuffer(gl.ARRAY_BUFFER, vp.shader.vbo)

	gl.BindFramebuffer(gl.FRAMEBUFFER, vp.framebuffer_id)
	gl.Viewport(0, 0, width, height) // TODO hardcoded
	gl.ClearColor(0, 0, 0, 1)
	gl.Clear(gl.COLOR_BUFFER_BIT)
	gl.Clear(gl.DEPTH_BUFFER_BIT)

	// set the vertex attribute stuff
	gl.EnableVertexAttribArray(0) // pos
	gl.EnableVertexAttribArray(1) // color in

	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Viewport_Vertex), offset_of(Viewport_Vertex, pos))
	gl.VertexAttribPointer(1, 4, gl.FLOAT, false, size_of(Viewport_Vertex), offset_of(Viewport_Vertex, color))

	// NOTE: A real implementation should do better than this about camera control!
	ar: f32 = f32(width) / f32(height)
	proj := glm.mat4Ortho3d(-ar, ar, -1, 1, 0.1, 20) // half widths, half heights, near, far
	view := glm.mat4LookAt({2 + 0.05 * math.cos(app.t * 0.9), 2 + 0.3 * math.sin(app.t), 1.0}, {0, 0, 0}, {0, 0, 1}) // eye location, what to look at, up vector
	flip_view := glm.mat4{1.0, 0, 0, 0, 0, -1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1} // flip camera space -Y becasue microui expects things upside down
	u_transform := flip_view * proj * view
	gl.UniformMatrix4fv(vp.shader.uniforms["MVP"].location, 1, false, &u_transform[0, 0])
}


viewport_draw :: proc(vp: ^Viewport, width, height: i32) {
	viewport_draw_prepare(vp, width, height)

	// context.temp_allocator is assumed to be cleared once per frame (no leak here)
	lineset := make([dynamic]Viewport_Line, 0, 128, context.temp_allocator)

	// Draw the stuff in between
	line :: proc(v1, v2: glm.vec3) -> (res: Viewport_Line) {
		res.vert[0].pos = v1
		res.vert[1].pos = v2
		res.vert[0].color = {1.0, 0.5, 0.5, 1.0}
		res.vert[1].color = {0.5, 0.5, 1.0, 1.0}
		return
	}
	append(&lineset, line({0.2, 0.1, 0.0}, {0.2, 0.6, 0.0}))
	append(&lineset, line({0.2, 0.6, 0.5}, {0.2, 0.6, 0.0}))
	append(&lineset, line({0.2, 0.6, 0.5}, {0.2, 0.1, 0.5}))
	append(&lineset, line({0.2, 0.1, 0.0}, {0.2, 0.1, 0.5}))

	// Draw a coordinate system to more easily debug some things
	{
		x := Viewport_Line{}
		x.vert[0] = Viewport_Vertex {
			pos = {0.0, 0.0, 0.0},
			color = {1.0, 0.0, 0.0, 1.0},
		}
		x.vert[1] = Viewport_Vertex {
			pos = {1.0, 0.0, 0.0},
			color = {1.0, 0.0, 0.0, 1.0},
		}
		append(&lineset, x)

		y := Viewport_Line{}
		y.vert[0] = Viewport_Vertex {
			pos = {0.0, 0.0, 0.0},
			color = {0.0, 1.0, 0.0, 1.0},
		}
		y.vert[1] = Viewport_Vertex {
			pos = {0.0, 1.0, 0.0},
			color = {0.0, 1.0, 0.0, 1.0},
		}
		append(&lineset, y)

		z := Viewport_Line{}
		z.vert[0] = Viewport_Vertex {
			pos = {0.0, 0.0, 0.0},
			color = {0.0, 0.0, 1.0, 1.0},
		}
		z.vert[1] = Viewport_Vertex {
			pos = {0.0, 0.0, 1.0},
			color = {0.0, 0.0, 1.0, 1.0},
		}
		append(&lineset, z)
	}

	viewport_draw_flush(vp, &lineset)
}


// Push data to the GPU and call draw! CAUTION: also gives up the framebuffer.
viewport_draw_flush :: proc(vp: ^Viewport, lineset: ^[dynamic]Viewport_Line) {
	bytes_to_push := len(lineset) * size_of(lineset[0])
	lines_to_draw := i32(2 * len(lineset))
	gl.BufferData(gl.ARRAY_BUFFER, bytes_to_push, raw_data(lineset[:]), gl.DYNAMIC_DRAW)
	gl.DrawArrays(gl.LINES, 0, lines_to_draw)
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}


shader_lines_vertex: string = `
#version 330 core
layout(location=0) in vec3 position; // model space
layout(location=1) in vec4 color_in;

uniform mat4 MVP;
out vec4 color;

void main(){
	gl_Position = MVP * vec4(position, 1);
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
