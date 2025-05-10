package miniui
import "core:fmt"
import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"
import SDL "vendor:sdl2"

Gui :: struct {
	ctx:             Context,
	bg:              Color,

	// current window dimensions (px) provided to draw_prepare()
	window_width:    i32,
	window_height:   i32,
	clip:            Rect,

	// standard_atlas is the one that comes bundled with microui/miniui
	atlas:           Texture,
	shader:          Shader,
	last_texture_id: u32,
}


Shader :: struct {
	program:  u32,
	uniforms: map[string]gl.Uniform_Info,
	vao:      u32,
	vbo:      u32,
	ebo:      u32,
}


// Initialize everything to do with the GUI: microui and GPU shaders.
// CAUTION: bad stuff seems to happen if this is on the stack!
init :: proc(allocator := context.allocator) -> ^Gui {
	context.allocator = allocator

	// Need the result to be used and passed around. Internally calls microui.init()
	gui: ^Gui = new(Gui, context.allocator)

	gpu_init_default_atlas(gui)
	gpu_init_shader(gui)

	im_init(&gui.ctx)
	gui.ctx.text_width = default_atlas_text_width
	gui.ctx.text_height = default_atlas_text_height

	free_all(context.temp_allocator)

	return gui
}

// Once the frame is built and ready to draw, call this to active the right shader.
draw_prepare :: proc(gui: ^Gui, window_width, window_height: i32) {

	gl.BindBuffer(gl.ARRAY_BUFFER, 0) // TODO is this needed?
	gl.UseProgram(0)

	gl.UseProgram(gui.shader.program)
	gl.BindBuffer(gl.ARRAY_BUFFER, gui.shader.vbo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gui.shader.ebo)

	// Setup the graphics pipeline vertex attributes
	gl.EnableVertexAttribArray(0) // pos
	gl.EnableVertexAttribArray(1) // color tint
	gl.EnableVertexAttribArray(2) // uv
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos)) // within the buffer where is position?
	gl.VertexAttribPointer(1, 4, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, col)) // where is color? stride?
	gl.VertexAttribPointer(2, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, uv))

	// Bind this texture by default
	gl.BindTexture(gl.TEXTURE_2D, gui.atlas.texture_id)
	gui.last_texture_id = gui.atlas.texture_id

	gui.window_width = window_width
	gui.window_height = window_height
}


//////////////////////////////////////////////////////////////////////////////////////////////////
// User Texture
Texture :: struct {
	texture_id: u32, // OpenGL

	// These are the raw (unscaled, uncropped) dimensions of the texture
	width:      i32,
	height:     i32,
	inv_width:  f32,
	inv_height: f32,
}


texture_create :: proc(id: u32, width, height: i32) -> Texture {
	tex := Texture{}
	tex.texture_id = id
	tex.width = width
	tex.inv_width = 1.0 / f32(width)

	tex.height = height
	tex.inv_height = 1.0 / f32(height)
	return tex
}


//////////////////////////////////////////////////////////////////////////////////////////////////
// Draw execute function
@(private)
gpu_render_texture :: proc(
	gui: ^Gui,
	vertices: ^[dynamic]Vertex,
	indices: ^[dynamic]u16,
	dst: Rect,
	src: Rect,
	tex: Texture,
	color: Color,
	scale_unity: bool = true,
) {
	// Build and render a textured quad out of two triangles.
	// src and dst are in units of pixels, because this is what microui is using

	// SDL (and thus microui) coordinates are measured down from the top left corner,
	// but my screenspace is reasonable OpenGL UV cordiantes are [0,1]; starting in the lower left.
	// But assume that the image is loaded in memory with Y backwards
	// p(0,0) g(-1,+1) uv(0,1)                      p(1000,0) g(+1,+1) uv(1,1)
	//
	//
	// p(0,1000) g(-1,-1) uv(0,0)                   p(1000,1000) g(+1,-1) uv(1,0)

	// Only change what texture the GPU is looking at as needed
	if gui.last_texture_id != tex.texture_id {
		draw_flush(gui, vertices, indices) // TODO can this be removed even though texture is changing?
		gl.BindTexture(gl.TEXTURE_2D, tex.texture_id)
		gui.last_texture_id = tex.texture_id
	}

	dst := dst
	src := src

	// X-Clipping
	scale_width: f32 = f32(src.w) / f32(dst.w)
	// Left side clip
	if dst.x < gui.clip.x {
		delta := gui.clip.x - dst.x // positive
		dst.x += delta
		dst.w -= delta

		delta_scale := i32(f32(delta) * f32(scale_width))
		src.x += delta_scale
		src.w -= delta_scale
	}
	// Right side clip
	if dst.x + dst.w > gui.clip.x + gui.clip.w {
		delta := (dst.x + dst.w) - (gui.clip.x + gui.clip.w) // positive
		dst.w -= delta

		delta_scale := i32(f32(delta) * f32(scale_width))
		src.w -= delta_scale
	}
	// Early out if the texture ends up not being shown at all.
	if dst.w <= 0 {
		return
	}

	// Y-clipping
	scale_height: f32 = f32(src.h) / f32(dst.h)
	// Top side clip
	if dst.y < gui.clip.y {
		delta := gui.clip.y - dst.y // positive
		dst.y += delta
		dst.w -= delta

		delta_scale := i32(f32(delta) * f32(scale_height))
		src.y += delta_scale
		src.h -= delta_scale
	}
	// Bottom side clip
	if dst.y + dst.h > gui.clip.y + gui.clip.h {
		delta := (dst.y + dst.h) - (gui.clip.y + gui.clip.h)
		dst.h -= delta

		delta_scale := i32(f32(delta) * f32(scale_height))
		src.h -= delta_scale
	}
	// Early out if the texture ends up not being shown at all.
	if dst.h <= 0 {
		return
	}


	// specify vertex position in screenspace coordiantes (assume the camera gets sorted out)
	// specify vertex UV coordinates based on where to pull from the texture atlas
	// specify vertex color (tint) based on the mu color

	// This is inverse tinting... so giving color=0 will just cause color not to change? // TODO check the shader too
	v_color: glm.vec4 = {1.0 - f32(color.r) / 255.0, 1.0 - f32(color.g) / 255.0, 1.0 - f32(color.b) / 255.0, 1.0 - f32(color.a) / 255.0}
	zpos: f32 = 1

	// TODO this is hardcoded to be looking at the default texture atlas!
	// PERFORMANCE: store inv_window_dims in the context; only cast and divide once per frame
	// PERFORMANCE: float and inverted dimensions of the texture?

	v_left_top: Vertex = {
		pos = {2.0 * f32(dst.x) / f32(gui.window_width) - 1.0, 1.0 - 2.0 * f32(dst.y) / f32(gui.window_height), zpos},
		uv  = {f32(src.x) * tex.inv_width, f32(src.y) * tex.inv_height},
		col = v_color,
	}
	v_left_bottom: Vertex = {
		pos = {2.0 * f32(dst.x) / f32(gui.window_width) - 1.0, 1.0 - 2.0 * f32(dst.y + dst.h) / f32(gui.window_height), zpos},
		uv  = {f32(src.x) * tex.inv_width, f32(src.y + src.h) * tex.inv_height},
		col = v_color,
	}
	v_right_bottom: Vertex = {
		pos = {2.0 * f32(dst.x + dst.w) / f32(gui.window_width) - 1.0, 1.0 - 2.0 * f32(dst.y + dst.h) / f32(gui.window_height), zpos},
		uv  = {f32(src.x + src.w) * tex.inv_width, f32(src.y + src.h) * tex.inv_height},
		col = v_color,
	}

	v_right_top: Vertex = {
		pos = {2.0 * f32(dst.x + dst.w) / f32(gui.window_width) - 1.0, 1.0 - 2.0 * f32(dst.y) / f32(gui.window_height), zpos},
		uv  = {f32(src.x + src.w) * tex.inv_width, f32(src.y) * tex.inv_height},
		col = v_color,
	}

	idx: u16 = u16(len(vertices))

	// Append to the rendering lists
	append(vertices, v_left_top, v_left_bottom, v_right_bottom, v_right_top)

	// For each face give the three vertices to use
	append(indices, idx + 0, idx + 1, idx + 2, idx + 0, idx + 2, idx + 3)
}


@(private)
// The real deal: send buffered data to the GPU and call OpenGL Draw!
draw_flush :: proc(gui: ^Gui, vertices: ^[dynamic]Vertex, indices: ^[dynamic]u16) {

	// Actually do the call arrays, activate the right shader, etc.
	gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(vertices[0]), raw_data(vertices^), gl.DYNAMIC_DRAW)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(indices[0]), raw_data(indices^), gl.DYNAMIC_DRAW)

	{
		// PERFORMANCE: Send the uniform less frequently
		// Flip to +Z up but otherwise boring
		tf := glm.mat4{1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, -1.0, 0, 0, 0, 0, 1}

		proj := glm.mat4Ortho3d(-1, 1, -1, 1, 0.1, 100) // half widths, half heights, near, far
		view := glm.mat4LookAt({0, 0, 2}, {0, 0, 0}, {0, 1, 0}) // eye location, what to look at, up vector
		u_transform := proj * view * tf

		gl.UniformMatrix4fv(gui.shader.uniforms["u_transform"].location, 1, false, &u_transform[0, 0])
	}

	gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_SHORT, nil)

	// Reset draw_queues
	clear(vertices)
	clear(indices)
}


// Convert the imgui instructions into GPU vertices, then draw_flush().
draw :: proc(gui: ^Gui, allocator := context.allocator) {
	// Build list of quads to be rendered with new UV coordiantes based on pulling from the right
	// places in the gui texture atlas
	// The example version of this uses SDL software rendering functions


	// Vertex and vertex indices to be submitted to the render pipeline
	// Recommend the allocator be a temp allocator of some sort
	vertices := make([dynamic]Vertex, allocator = allocator)
	indices := make([dynamic]u16, allocator = allocator)

	gl.Disable(gl.DEPTH_TEST)
	gl.Disable(gl.CULL_FACE)

	gl.Enable(gl.TEXTURE_2D)
	// get information about the current maximum viewport

	gl.Viewport(0, 0, gui.window_width, gui.window_height)
	gui.clip = unclipped_rect

	// fmt.printf("[UI] Frame Record Start!\n")

	command_backing: ^Command
	for variant in next_command_iterator(&gui.ctx, &command_backing) {
		switch cmd in variant {
		case ^Command_Text:
			// fmt.printf("  text: %v\n", cmd.str)
			// Pull rects from the ui texture atlas
			dst := Rect{cmd.pos.x, cmd.pos.y, 0, 0}
			for ch in cmd.str do if ch & 0xc0 != 0x80 {
				r := min(int(ch), 127)
				src := default_atlas[DEFAULT_ATLAS_FONT + r]
				// fmt.printf("Text color: %v", cmd.color)
				dst.w = src.w
				dst.h = src.h
				gpu_render_texture(gui, &vertices, &indices, dst, src, gui.atlas, cmd.color)
				dst.x += dst.w
			}

		case ^Command_Rect:
			// fmt.printf("  rect: %v\n", cmd.color)
			draw_flush(gui, &vertices, &indices)

			// Temporary set draw bounds nd use gl.Clear() to draw a rectangle
			// TODO rewrite to draw a tinted quad and be able to just add this as another
			// quad to be drawn by the GPU program; right now this is a lot of GPU calls!
			gl.Enable(gl.SCISSOR_TEST)
			gl.Scissor(cmd.rect.x, gui.window_height - cmd.rect.y - cmd.rect.h, cmd.rect.w, cmd.rect.h)
			gl.ClearColor(f32(cmd.color.r) / 255.0, f32(cmd.color.g) / 255.0, f32(cmd.color.b) / 255.0, f32(cmd.color.a) / 255.0)
			gl.Clear(gl.COLOR_BUFFER_BIT)

			// Restore viewport
			gl.Scissor(0, 0, gui.window_width, gui.window_height)
			gl.Disable(gl.SCISSOR_TEST)

		case ^Command_Icon:
			// fmt.printf("  icon: %v\n", cmd.id)
			src := default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w) / 2
			y := cmd.rect.y + (cmd.rect.h - src.h) / 2
			gpu_render_texture(gui, &vertices, &indices, Rect{x, y, src.w, src.h}, src, gui.atlas, cmd.color)

		case ^Command_Clip:
			// fmt.printf("\033[0;31m  clip: %v\033[0m\n", cmd.rect)
			// Clip information is given in the coordinate system of the entire window.
			gui.clip = cmd.rect

		case ^Command_Jump:
			// This is handled by mu.next_command_iterator() to call commands in the right sequence
			// and should not be seen by this codepath.
			panic("Graphics drawing encountered mu.Command_Jump!")

		case ^Command_Image:
			// fmt.printf("  image\n")

			gpu_render_texture(
				gui,
				&vertices,
				&indices,
				Rect{cmd.dst.x, cmd.dst.y, cmd.dst.w, cmd.dst.h}, // TODO need to give it some space!
				cmd.src,
				cmd.tex,
				cmd.color,
				scale_unity = false,
			)
		}

	}

	draw_flush(gui, &vertices, &indices)

	// Restore the 3D OpenGL State
	gl.Disable(gl.TEXTURE_2D)
	gl.Disable(gl.SCISSOR_TEST)
	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.CULL_FACE)
	gl.Viewport(0, 0, gui.window_width, gui.window_height)
	gl.Scissor(0, 0, gui.window_width, gui.window_height)
}


// Draw finish up functions

//////////////////////////////////////////////////////////////////////////////////////////////////
// Init Functions


// Convert the default atlas into a full RGBA texture and push it to the GPU
@(private)
gpu_init_default_atlas :: proc(gui: ^Gui) {

	// The atlas is expanded in CPU-memory to form a full texture for the GPU. But after loading to the GPU,
	// the CPU memory isn't required anymore.
	lenpixels := DEFAULT_ATLAS_WIDTH * DEFAULT_ATLAS_HEIGHT
	pixels := make([^]u8, 4 * lenpixels, allocator = context.temp_allocator)
	for i := 0; i < lenpixels; i += 1 {
		pixels[4 * i] = 0xff
		pixels[4 * i + 1] = 0xff
		pixels[4 * i + 2] = 0xff
		pixels[4 * i + 3] = default_atlas_alpha[i]
	}

	gui.atlas = texture_create(0, DEFAULT_ATLAS_WIDTH, DEFAULT_ATLAS_HEIGHT)

	gl.GenTextures(1, &gui.atlas.texture_id)
	gl.BindTexture(gl.TEXTURE_2D, gui.atlas.texture_id)

	gl.TexImage2D(
		target = gl.TEXTURE_2D,
		level = 0,
		internalformat = gl.RGBA,
		width = DEFAULT_ATLAS_WIDTH,
		height = DEFAULT_ATLAS_HEIGHT,
		border = 0,
		format = gl.RGBA,
		type = gl.UNSIGNED_BYTE,
		pixels = rawptr(pixels),
	)

	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)
	gl.BindTexture(gl.TEXTURE_2D, 0)
}


// Setup the provided gui context with a shader for rendering.
@(private)
gpu_init_shader :: proc(gui: ^Gui) {
	gui.shader = Shader{}

	program_ok: bool
	// Uses a very simple textured-quad shader, with vertices fully prepared on the CPU beforehand.
	gui.shader.program, program_ok = gl.load_shaders_source(shader_3D_vertex, shader_3D_fragment)
	if !program_ok {
		panic("Failed to create GLSL program for miniui rendering.")
	}
	gl.UseProgram(gui.shader.program)

	gui.shader.uniforms = gl.get_uniforms_from_program(gui.shader.program)

	gl.GenVertexArrays(1, &gui.shader.vao)
	gl.GenBuffers(1, &gui.shader.vbo)
	gl.GenBuffers(1, &gui.shader.ebo)
}

//////////////////////////////////////////////////////////////////////////////////////////////////
// The Shaders
// These are basic 3D textured quad shaders. So this may cost some additional GPU calls if the rest
// of the application is using essentially a second copy of this same shader.

Vertex :: struct {
	pos: glm.vec3,
	col: glm.vec4, // tinting
	uv:  glm.vec2,
}

shader_3D_vertex: string = `
    #version 330 core
    layout(location=0) in vec3 a_position;
    layout(location=1) in vec4 a_color;
    layout(location=2) in vec2 vertex_uv;
    out vec4 v_color;
    out vec2 UV;
    uniform mat4 u_transform;
    void main() {	
    	gl_Position = u_transform * vec4(a_position, 1.0);
    	v_color = a_color;
    	UV = vertex_uv;
    }
`


shader_3D_fragment: string = `
    #version 330 core
    in vec4 v_color;
    in vec2 UV;
    out vec4 o_color;
    uniform sampler2D texture_sampler;
    void main() {
    	// Use vertex colors to tint the entity
        vec4 tint = 1 - v_color;
    	o_color = texture(texture_sampler, UV) * tint;
        if (o_color.a < 0.05){
            discard;
        }
    }
`

