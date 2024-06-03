package plot
import "core:log"
import glm "core:math/linalg/glsl"
import gl "vendor:OpenGL"

// Get a framebuffer provided by/for something

// BACKGROUND COLOR
// AXIS & LABEL COLOR

PLOT_DEFAULT_COLOR_BACKGROUND :: glm.vec4{0.05, 0.05, 0.05, 1.0}
PLOT_DEFAULT_COLOR_ANNOTATION :: glm.vec4{0.5, 0.7, 0.5, 1.0}

// TODO: How to add text labels?

// PERFORMANCE: consider a separate PlotRenderer struct so shader program setup isn't duplicate work
PlotRenderer :: struct {
	program:  u32,
	uniforms: map[string]gl.Uniform_Info,
	vao:      u32,
}


Plot :: struct {
	framebuffer:            u32,
	framebuffer_rgb:        u32,
	framebuffer_depth:      u32,
	framebuffer_width_max:  i32,
	framebuffer_height_max: i32,
	color_background:       glm.vec4,
	color_annotation:       glm.vec4,

	// the current display portion
	range_x:                [2]f32,
	range_y:                [2]f32,

	// Pointers (via slice) to the actual data being plotted
	data:                   [dynamic]Dataset,

	// Using the same shader to draw grid elements, so we need VBOs
	vbo_grid_x:             u32,
	vbo_grid_y:             u32,
}


Dataset :: struct {
	x:     []f32,
	y:     []f32,
	color: glm.vec4,
	vbo_x: u32,
	vbo_y: u32,
}


render_init :: proc(allocator := context.allocator) -> (rend: ^PlotRenderer) {
	// STEP 1: Setup the shader to draw Plots. 
	context.allocator = allocator

	rend = new(PlotRenderer)

	// Init shader
	{
		program_ok: bool
		rend.program, program_ok = gl.load_shaders_source(shader_line_vertex, shader_line_fragment)
		if !program_ok {
			panic("failed to create GLSL program for Plot rendering.")
		}
		gl.UseProgram(rend.program)

		rend.uniforms = gl.get_uniforms_from_program(rend.program)

		gl.GenVertexArrays(1, &rend.vao)
	}

	return rend
}


plot_init :: proc(
	width, height: i32,
	color_background := PLOT_DEFAULT_COLOR_BACKGROUND,
	color_annotation := PLOT_DEFAULT_COLOR_ANNOTATION,
) -> (
	plot: Plot,
) {
	// STEP 2: Create a Plot
	// width, height of maximum framebuffer dimensions
	// Since this is calling GPU setup and allocations, it is recommended to do
	// this once during setup; not every frame.

	plot.color_background = color_background
	plot.color_annotation = color_annotation

	gl.CreateFramebuffers(1, &plot.framebuffer)
	log.debugf("Created framebuffer: %v", gl.GetError())

	plot.framebuffer_width_max = width
	plot.framebuffer_height_max = height

	// Color texture
	gl.CreateTextures(gl.TEXTURE_2D, 1, &plot.framebuffer_rgb)
	gl.TextureParameteri(plot.framebuffer_rgb, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TextureParameteri(plot.framebuffer_rgb, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.TextureParameteri(plot.framebuffer_rgb, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(plot.framebuffer_rgb, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(plot.framebuffer_rgb, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	log.debugf("Created framebuffer texture: %v", gl.GetError())

	gl.TextureStorage2D(plot.framebuffer_rgb, 1, gl.RGBA8, plot.framebuffer_width_max, plot.framebuffer_height_max)
	gl.NamedFramebufferTexture(plot.framebuffer, gl.COLOR_ATTACHMENT0, plot.framebuffer_rgb, 0)
	log.debugf("Setup framebuffer rgb: %v", gl.GetError())

	// Depth texture
	gl.CreateTextures(gl.TEXTURE_2D, 1, &plot.framebuffer_depth)
	gl.TextureStorage2D(plot.framebuffer_depth, 1, gl.DEPTH24_STENCIL8, plot.framebuffer_width_max, plot.framebuffer_height_max)
	gl.NamedFramebufferTexture(plot.framebuffer, gl.DEPTH_STENCIL_ATTACHMENT, plot.framebuffer_depth, 0)
	log.debugf("Framebuffer depth: %v", gl.GetError())

	// Creat the vertex buffers for the grid/ui stuff
	gl.GenBuffers(1, &plot.vbo_grid_x)
	gl.GenBuffers(1, &plot.vbo_grid_y)

	return plot
}


dataset_add :: proc(plot: ^Plot, x, y: []f32, color := glm.vec4{0.8, 0.0, 0.8, 1.0}) -> (dset: ^Dataset) {
	// STEP 3: Create a Dataset to be plotted, and send the data to the GPU.
	// TODO: how does this work if ther isn't data available yet? 
	append(&plot.data, Dataset{x = x[:], y = y[:]})
	dset = &plot.data[len(plot.data) - 1]

	gl.GenBuffers(1, &dset.vbo_x)
	gl.GenBuffers(1, &dset.vbo_y)
	dset.color = color

	dataset_update(dset, x, y)
	return dset
}

// TODO set of procedures to call to change plot pan & zoom
// have the user implement how these get called

dataset_update :: proc(dset: ^Dataset, x, y: []f32) {
	// Update pointers and send new data to the GPU
	assert(len(x) == len(y))
	dset.x = x
	dset.y = y
	gl.BindBuffer(gl.ARRAY_BUFFER, dset.vbo_x)
	gl.BufferData(gl.ARRAY_BUFFER, len(x) * size_of(x[0]), &x[0], gl.STATIC_DRAW)
	gl.BindBuffer(gl.ARRAY_BUFFER, dset.vbo_y)
	gl.BufferData(gl.ARRAY_BUFFER, len(y) * size_of(y[0]), &y[0], gl.STATIC_DRAW)
}


draw :: proc(rend: ^PlotRenderer, plot: ^Plot, width, height: i32) {
	// STEP 4: Render the Plot to its framebuffer
	// Displaying the framebuffer is left to the user

	gl.UseProgram(rend.program)

	gl.BindFramebuffer(gl.FRAMEBUFFER, plot.framebuffer)
	gl.Viewport(0, 0, width, height)
	gl.ClearColor(plot.color_background[0], plot.color_background[1], plot.color_background[2], plot.color_background[3])
	gl.Clear(gl.COLOR_BUFFER_BIT)
	gl.Clear(gl.DEPTH_BUFFER_BIT)

	// calculate and set transform uniform
	{
		// TODO redo this to be nicer for just 2D stuff and changing
		ar := f32(width) / f32(height)
		proj := glm.mat4Ortho3d(-ar, ar, -1, 1, 0, 1)
		view := glm.mat4LookAt({0.0, 0.0, -1.0}, {0.0, 0.0, 0.0}, {0.0, 1.0, 0.0})
		flip_view := glm.mat4{1.0, 0, 0, 0, 0, -1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1} // flip camera space -Y becasue microui expects things upside down 
		u_transform: glm.mat4x4 = flip_view * proj * view
		gl.UniformMatrix4fv(rend.uniforms["u_transform"].location, 1, false, &u_transform[0][0])
	}

	gl.BindVertexArray(rend.vao)
	dz: f32 = 1.0 / (3 + f32(len(plot.data)))
	z: f32 = -2 * dz

	for &dataset in plot.data {
		// set color uniform
		gl.Uniform4fv(rend.uniforms["color"].location, 1, &dataset.color[0])
		gl.Uniform1f(rend.uniforms["z"].location, z)
		z -= dz

		// link these VBOs to this ARRAY_BUFFER
		gl.BindBuffer(gl.ARRAY_BUFFER, dataset.vbo_x)
		gl.VertexAttribPointer(0, 1, gl.FLOAT, false, 0, uintptr(0))
		gl.EnableVertexAttribArray(0)

		gl.BindBuffer(gl.ARRAY_BUFFER, dataset.vbo_y)
		gl.VertexAttribPointer(1, 1, gl.FLOAT, false, 0, uintptr(0))
		gl.EnableVertexAttribArray(1)

		// draw with the offset
		gl.DrawArrays(gl.LINE_STRIP, 0, cast(i32)len(dataset.x))
	}

	// set color uniform for grid/UI
	gl.Uniform4fv(rend.uniforms["color"].location, 1, &plot.color_annotation[0])
	gl.Uniform1f(rend.uniforms["z"].location, -dz)

	// Fill the UI VBOs with whatever data they need
	// PERFORMANCE: only if the view has changed?
	// TODO : so much better grid stuff, respond to scale add grid instead of just axis marks, etc.
	dg: f32 = 0.0025 // scale by pixels
	grid_x: []f32 = {-1, 1, -1, 1, dg, dg, -dg, -dg}
	grid_y: []f32 = {dg, dg, -dg, -dg, -1, 1, -1, 1}


	// link the UI VBOs to this ARRAY_BUFFER
	gl.BindBuffer(gl.ARRAY_BUFFER, plot.vbo_grid_x)
	gl.BufferData(gl.ARRAY_BUFFER, len(grid_x) * size_of(grid_x[0]), &grid_x[0], gl.STATIC_DRAW)
	gl.VertexAttribPointer(0, 1, gl.FLOAT, false, 0, uintptr(0))
	gl.EnableVertexAttribArray(0)

	gl.BindBuffer(gl.ARRAY_BUFFER, plot.vbo_grid_y)
	gl.BufferData(gl.ARRAY_BUFFER, len(grid_y) * size_of(grid_y[0]), &grid_y[0], gl.STATIC_DRAW)
	gl.VertexAttribPointer(1, 1, gl.FLOAT, false, 0, uintptr(0))
	gl.EnableVertexAttribArray(1)

	// // use non strip mode for the UI elements
	gl.DrawArrays(gl.LINES, 0, cast(i32)len(grid_x))

	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}

/////////////////////////////////////////////////////////////////////////////////////////////////
// 

shader_line_vertex: string = `
    #version 330 core
    layout(location=0) in float x;
    layout(location=1) in float y;
    out vec4 v_color;
    uniform mat4 u_transform;
    uniform vec4 color;
    uniform float z;
    void main() {	
    	gl_Position = u_transform * vec4(x, y, z, 1.0);
    	v_color = color;
    }
`

shader_line_fragment: string = `
    #version 330 core
    in vec4 v_color;
    out vec4 o_color;
    void main() {
	    o_color = v_color;
    }
`

// https://en.wikibooks.org/wiki/OpenGL_Programming/Scientific_OpenGL_Tutorial_02
// Make some 1-D VBOs
// https://stackoverflow.com/questions/64476062/multiple-vbos-in-one-vao?rq=3
