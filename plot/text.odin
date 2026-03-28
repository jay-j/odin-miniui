package plot

import "base:runtime"
import "core:log"
import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"
import font "vendor:fontstash"

Textbox_Type :: enum {
	NONE,
	TITLE,
	LABEL_X,
	LABEL_Y,
	LEGEND,
	AXIS_TIC,
}

Textbox :: struct {
	type: Textbox_Type,
	text: string,
	pos:  [2]f32,
}


FONT_SIZE_DEFAULT :: [Textbox_Type]f32 {
	.NONE     = 12,
	.TITLE    = 24,
	.LABEL_X  = 12,
	.LABEL_Y  = 12,
	.LEGEND   = 12,
	.AXIS_TIC = 8,
}

// TODO: Check out examples in the launchfest UI code


render_init_font :: proc(rend: ^PlotRenderer) {
	rend.font_size = FONT_SIZE_DEFAULT

	// Setup OpenGl shaders for font (textured quad) rendering
	{
		program_ok: bool
		// Uses a very simple textured-quad shader, with vertices fully prepared on the CPU beforehand.
		rend.font_shader.program, program_ok = gl.load_shaders_source(shader_2D_vertex, shader_2D_fragment)
		if !program_ok {
			log.panic("Failed to create GLSL program for plot font rendering.")
		}
		gl.UseProgram(rend.font_shader.program)

		rend.font_shader.uniforms = gl.get_uniforms_from_program(rend.font_shader.program)

		gl.GenVertexArrays(1, &rend.font_shader.vao)
		gl.GenBuffers(1, &rend.font_shader.vbo)
		gl.GenBuffers(1, &rend.font_shader.ebo)
	}
	// Generate a GPU texture for the font atlas
	{
		gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1) // There will be no data gaps between rows of pixels
		gl.GenTextures(1, &rend.font_texture_id)
		gl.BindTexture(gl.TEXTURE_2D, rend.font_texture_id)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
		gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	}

	// HACK: Guessing at the atlas dimensions and starting corner
	// TODO: What if the atlas runs out of space?
	font.Init(&rend.font_ctx, 1024, 1024, .TOPLEFT)
	rend.font_ctx.userData = rend
	rend.font_ctx.callbackUpdate = font_atlas_to_gpu
	font.AddFontPath(&rend.font_ctx, "Liberation Mono", "liberation-mono.ttf")
	rend.font_atlas_dirty = true
}


// font.CodepointWidth
// font.LineBounds
// Check font.ValidateTexture() to determine if the texture needs an update on the GPU
//
// There is a font.State type for size and color and stuff
// and a corresponding PushState and PopState procs
//
// Something called a TextIterInit(), some kind of helper for stepping through one at a time
// and will fill quad information for that glyph
// run TextBounds to figure out how big the line is
// TODO: How does this fontstash handle multiple sizes??


// Draw all the text boxes associated with the given plot
draw_text :: proc(rend: ^PlotRenderer, plot: ^Plot, u_transform: glm.mat4x4) {

	textboxes: []Textbox // BUG placeholder since this system is being removed and overhauled

	runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

	// PERFORMANCE: How many characters should be reserved here?
	vertices := make([dynamic]Vertex, 0, 128, allocator = context.temp_allocator)
	indices := make([dynamic]u16, 0, 128, allocator = context.temp_allocator)

	font.BeginState(&rend.font_ctx)
	font.SetSize(&rend.font_ctx, 60) // Pixels
	font.SetAlignHorizontal(&rend.font_ctx, .CENTER)

	// BUG: What happens if a glyph isn't found in the atlas?

	// BUG: Must also iterate through the plot labels.. make the legend a separate proc?
	for tbox in textboxes {
		// log.debugf("Queue rendering for textbox: %v", tbox.text)
		// BUG: Get the desired position correctly. Offset by center or stuff.
		// TextIterInit() will measure and offset horizontal correctly to center
		// BUG: The scale needs to be correct for the positions to be correct here?
		// This seems to use a "pixels" coordinate system
		textiter := font.TextIterInit(&rend.font_ctx, 400 * tbox.pos.x, 400 * tbox.pos.y, tbox.text)
		quad: font.Quad
		for font.TextIterNext(&rend.font_ctx, &textiter, &quad) {
			draw_quad_textured(&vertices, &indices, quad)
		}
	}

	// BUG Draw legends

	font.EndState(&rend.font_ctx)


	gl.Enable(gl.CULL_FACE)
	gl.Enable(gl.BLEND)
	gl.BlendEquation(gl.FUNC_ADD)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.Enable(gl.ALPHA_TEST)

	gl.UseProgram(rend.font_shader.program)

	gl.BindTexture(gl.TEXTURE_2D, rend.font_texture_id)
	gl.Enable(gl.TEXTURE_2D)

	gl.BindBuffer(gl.ARRAY_BUFFER, rend.font_shader.vbo)
	gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, rend.font_shader.ebo)

	// Setup the graphics pipeline vertex attributes
	gl.EnableVertexAttribArray(0) // pos
	gl.EnableVertexAttribArray(1) // uv
	gl.VertexAttribPointer(0, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, pos))
	gl.VertexAttribPointer(1, 2, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, uv))


	// Make sure the GPU has the latest font atlas
	gl.BindTexture(gl.TEXTURE_2D, rend.font_texture_id)
	// if rend.font_atlas_dirty {
	// 	log.warnf("Updating out-of-date GPU font atlas texture")
	// 	font_atlas_to_gpu(rend)
	// }

	// Then do the font rendering
	// Actually do the call arrays, activate the right shader, etc.
	gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(vertices[0]), raw_data(vertices), gl.DYNAMIC_DRAW)
	gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(indices) * size_of(indices[0]), raw_data(indices), gl.DYNAMIC_DRAW)

	// log.debugf("vertices:\n %#v", vertices[:])
	// assert(false, "we're done")

	{
		// PERFORMANCE: Send the uniform less frequently
		// Flip to +Z up but otherwise boring
		// tf := glm.mat4{1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, -1.0, 0, 0, 0, 0, 1}
		// proj := glm.mat4Ortho3d(-1, 1, -1, 1, 0.1, 100) // half widths, half heights, near, far
		// view := glm.mat4LookAt({0, 0, 2}, {0, 0, 0}, {0, 1, 0}) // eye location, what to look at, up vector
		// u_transform_alt := proj * view * tf
		// log.debugf("u transform alt: %#v", u_transform_alt)
		// log.debugf("U transform: %#v", u_transform)

		// BUG: Directly copying this doesn't work.. the Y is inverted.
		// This probably points to a larger challenge with sorting out the coordinate systems here.

		// Need the text appearance to not change with the plot.scale_mode
		// So can't re-use the u_transform from drawing that is stretching things out

		u_transform := u_transform
		gl.UniformMatrix4fv(rend.font_shader.uniforms["u_transform"].location, 1, false, &u_transform[0, 0])
	}

	// log.debugf("Drawing %v indices", len(indices))

	color := glm.vec4{1.0, 1, 0.2, 1.0}
	gl.Uniform4fv(rend.font_shader.uniforms["in_color"].location, 1, &color[0])

	gl.DrawElements(gl.TRIANGLES, i32(len(indices)), gl.UNSIGNED_SHORT, nil)
}


// Given stats of a glyph in the atlas, and a position (in upper left pixel coords) in the screen,
// append the quad to the draw lists.
@(private)
draw_quad_textured :: proc(draw_vertices: ^[dynamic]Vertex, draw_indices: ^[dynamic]u16, glyph: font.Quad) {

	// Draw a quad (two triangles; 4 vertices; re-use vertices) for each letter
	glyph := glyph
	// HACK: Scaling in space by some crazy numbers. Related to the font size of things
	glyph.x0 *= 0.0025
	glyph.x1 *= 0.0025
	glyph.y0 *= 0.0025
	glyph.y1 *= 0.0025


	v_left_top: Vertex = {
		pos = {glyph.x0, glyph.y1},
		uv  = {glyph.s0, glyph.t1},
	}
	v_left_bottom: Vertex = {
		pos = {glyph.x0, glyph.y0},
		uv  = {glyph.s0, glyph.t0},
	}
	v_right_bottom: Vertex = {
		pos = {glyph.x1, glyph.y0},
		uv  = {glyph.s1, glyph.t0},
	}

	v_right_top: Vertex = {
		pos = {glyph.x1, glyph.y1},
		uv  = {glyph.s1, glyph.t1},
	}

	idx: u16 = u16(len(draw_vertices))

	// Append to the rendering lists
	append(draw_vertices, v_left_top, v_left_bottom, v_right_bottom, v_right_top)

	// For each face give the three vertices to use
	// Counter-clockwise is the winding order for front-facing (visible) triangles
	append(draw_indices, idx + 0, idx + 1, idx + 2, idx + 0, idx + 2, idx + 3)
}


// for the fontstash callbackUpdate()
font_atlas_to_gpu :: proc(data: rawptr, dirtyRect: [4]f32, textureData: rawptr) {
	// PERFORMANCE: Use the dirtyRect argument to only update the portion of the atlas that has changed
	// dirtyRect is [left, top, right, bottom]
	log.warnf("Updating out-of-date font atlas on the GPU")
	rend := cast(^PlotRenderer)data
	gl.BindTexture(gl.TEXTURE_2D, rend.font_texture_id)
	gl.TexImage2D(
		target = gl.TEXTURE_2D,
		level = 0,
		internalformat = gl.RED,
		width = i32(rend.font_ctx.width),
		height = i32(rend.font_ctx.height),
		border = 0,
		format = gl.RED,
		type = gl.UNSIGNED_BYTE, // TODO check
		pixels = raw_data(rend.font_ctx.textureData),
	)
	rend.font_atlas_dirty = false
}

//////////////////////////////////////////////////////////////////////////////////////////////////
// The Shaders
// These are basic 3D textured quad shaders. So this may cost some additional GPU calls if the rest
// of the application is using essentially a second copy of this same shader.
// TODO: This is almost the same shader and vertex definition used by the upper level minui render ... combine?

Shader :: struct {
	program:  u32,
	uniforms: map[string]gl.Uniform_Info,
	vao:      u32,
	vbo:      u32,
	ebo:      u32,
}

Vertex :: struct {
	pos: glm.vec2,
	// col: glm.vec4, // tinting
	uv:  glm.vec2,
}

RectF :: struct {
	x, y, w, h: f32,
}

shader_2D_vertex: string = `
    #version 330 core
    layout(location=0) in vec2 a_position;
    layout(location=1) in vec2 vertex_uv;
    out vec4 v_color;
    out vec2 UV;
    uniform vec4 in_color;
    uniform mat4 u_transform;
    void main() {
    	gl_Position = u_transform * vec4(a_position, -0.5, 1.0);
    	v_color = in_color;
    	UV = vertex_uv;
    }
`


shader_2D_fragment: string = `
    #version 330 core
    in vec4 v_color;
    in vec2 UV;
    out vec4 o_color;
    uniform sampler2D texture_sampler;
    void main() {
    	float alpha = texture(texture_sampler, UV).r;
     	o_color = vec4(v_color[0], v_color[1], v_color[2], v_color[3]*alpha);
     	if (o_color.a < 0.05) {
     		discard;
     	}
    }
`
