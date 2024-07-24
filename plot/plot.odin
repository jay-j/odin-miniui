package plot
import "core:fmt"
import "core:log"
import "core:math"
import glm "core:math/linalg/glsl"
import "core:slice"
import "core:testing"
import gl "vendor:OpenGL"

// Get a framebuffer provided by/for something

PLOT_DEFAULT_COLOR_BACKGROUND :: glm.vec4{0.05, 0.05, 0.05, 1.0}
PLOT_DEFAULT_COLOR_ANNOTATION :: glm.vec4{0.5, 0.7, 0.5, 1.0}

// TODO: How to add text labels?

Plot_Scale_Mode :: enum {
	Stretched = 0,
	Isotropic,
	Manual,
}


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
	color_graph_default:    glm.vec4,

	// the current display portion
	range_x:                [2]f32,
	range_y:                [2]f32,
	scale_mode:             Plot_Scale_Mode,

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


dataset_add :: proc(plot: ^Plot, x, y: []f32, color := glm.vec4{0.0, 0.0, 0.0, -1}, auto_range := false) -> (dset: ^Dataset) {
	// STEP 3: Create a Dataset to be plotted, and send the data to the GPU.
	// TODO: how does this work if ther isn't data available yet? 
	append(&plot.data, Dataset{x = x[:], y = y[:]})
	dset = &plot.data[len(plot.data) - 1]

	gl.GenBuffers(1, &dset.vbo_x)
	gl.GenBuffers(1, &dset.vbo_y)

	// If no color is given use a default changing value
	if color.a == -1 {
		dset.color = plot.color_graph_default
		// TODO increment the default color in HSV space
	} else {
		dset.color = color
	}

	dataset_update(dset, x, y)

	if auto_range {
		range_x: [2]f32 = {slice.min(x[:]), slice.max(x[:])}
		if range_x[0] < plot.range_x[0] {
			plot.range_x[0] = range_x[0]
		}
		if range_x[1] > plot.range_x[1] {
			plot.range_x[1] = range_x[1]
		}

		range_y: [2]f32 = {slice.min(y[:]), slice.max(y[:])}
		if range_y[0] < plot.range_y[0] {
			plot.range_y[0] = range_y[0]
		}
		if range_y[1] > plot.range_y[1] {
			plot.range_y[1] = range_y[1]
		}
	}

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

	// Expand the grid to the view rather than restricting it to the range of data.
	grid_bounds_x: [2]f32
	grid_bounds_y: [2]f32

	// calculate and set transform uniform
	{
		proj: glm.mat4x4
		if plot.scale_mode == .Stretched {
			proj = glm.mat4Ortho3d(plot.range_x[0], plot.range_x[1], plot.range_y[0], plot.range_y[1], 0, 1)
			copy(grid_bounds_x[:], plot.range_x[:])
			copy(grid_bounds_y[:], plot.range_y[:])

		} else if plot.scale_mode == .Isotropic {
			ar_pixels := f32(width) / f32(height) // aspect ratio of the available pixels
			ar_data: f32 = (plot.range_x[1] - plot.range_x[0]) / (plot.range_y[1] - plot.range_y[0])

			// if data is wider than the display, use the data to set the pixel ratio width and there is extra empty height
			if ar_data >= ar_pixels {
				ratio := (plot.range_x[1] - plot.range_x[0]) / f32(width) // unit per pixel
				half_height := 0.5 * f32(height) * ratio
				average_height: f32 = 0.5 * (plot.range_y[0] + plot.range_y[1])

				copy(grid_bounds_x[:], plot.range_x[:])
				grid_bounds_y = {average_height - half_height, average_height + half_height}

				proj = glm.mat4Ortho3d(plot.range_x[0], plot.range_x[1], grid_bounds_y[0], grid_bounds_y[1], 0, 1)


			} else {
				// if data is taller than the display, use the data to set the height and there is extra empty width
				ratio := (plot.range_y[1] - plot.range_y[0]) / f32(height)
				half_width := 0.5 * f32(width) * ratio
				average_width: f32 = 0.5 * (plot.range_x[0] + plot.range_x[1])

				copy(grid_bounds_y[:], plot.range_y[:])
				grid_bounds_x = {average_width - half_width, average_width + half_width}

				proj = glm.mat4Ortho3d(grid_bounds_x[0], grid_bounds_x[1], plot.range_y[0], plot.range_y[1], 0, 1)
			}
		}

		flip_view := glm.mat4{1.0, 0, 0, 0, 0, -1.0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 1} // flip camera space -Y becasue microui expects things upside down 
		u_transform: glm.mat4x4 = flip_view * proj
		gl.UniformMatrix4fv(rend.uniforms["u_transform"].location, 1, false, &u_transform[0][0])
	}

	gl.BindVertexArray(rend.vao)

	// OpenGL camera space goes from z=0 to -1
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
	grid_x: []f32 = {grid_bounds_x[0], grid_bounds_x[1], grid_bounds_x[0], grid_bounds_x[1], dg, dg, -dg, -dg}
	grid_y: []f32 = {dg, dg, -dg, -dg, grid_bounds_y[0], grid_bounds_y[1], grid_bounds_y[0], grid_bounds_y[1]}


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

rgb_to_hsv :: proc(rgb: glm.vec4) -> (hsv: glm.vec4) {
	// Floating point values; 0-1 not 0-255
	Cmax := max(rgb.r, rgb.g, rgb.b)
	Cmin := min(rgb.r, rgb.g, rgb.b)
	delta := Cmax - Cmin

	// Hue (0-1.0)
	if Cmax == rgb.r {
		hsv[0] = f32(60 * (int((rgb.g - rgb.b) / delta) % 6))
	} else if Cmax == rgb.g {
		hsv[0] = 60 * ((rgb.b - rgb.r) / delta + 2)
	} else {
		hsv[0] = 60 * ((rgb.r - rgb.g) / delta + 4)
	}
	hsv[0] /= 360.0

	// Saturation (0-1)
	if Cmax != 0 {
		hsv[1] = delta / Cmax
	}

	hsv[2] = Cmax // Value (0-1)
	hsv[3] = rgb[3] // Alpha (0-1)
	return hsv
}

@(test)
test_colors1 :: proc(t: ^testing.T) {
	rgb := glm.vec4{0.1, 0.9, 0.2, 1.0}
	hsv := rgb_to_hsv(rgb)
	fmt.printf("hsv: %v\n", hsv)
	testing.expect(t, abs(hsv[0] - 0.354167) < 0.001)
	testing.expect(t, abs(hsv[1] - 0.888889) < 0.001)
	testing.expect(t, abs(hsv[2] - 0.9) < 0.001)

	rgb2 := hsv_to_rgb(hsv)
	fmt.printf("rgb original  : %v\n", rgb)
	fmt.printf("rgb round trip: %v\n", rgb2)
	testing.expect(t, abs(rgb2[0] - rgb[0]) < 0.001)
	testing.expect(t, abs(rgb2[1] - rgb[1]) < 0.001)
	testing.expect(t, abs(rgb2[2] - rgb[2]) < 0.001)
}

hsv_to_rgb :: proc(hsv: glm.vec4) -> (rgb: glm.vec4) {
	// TODO this is currently broken SAD BUG FIX 
	C := hsv[2] * hsv[1]
	h360 := int(hsv[0] * 360)
	X: f32 = C * f32(1 - abs(((h360 / 60) % 2) - 1))
	m: f32 = hsv[2] - C
	fmt.printf("h360=%v        m=%v\n", h360, m)
	switch v := math.floor(f32(h360 / 60)); v {
	case 0:
		rgb = {C, X, 0, 0}
	case 1:
		rgb = {X, C, 0, 0}
	case 2:
		fmt.printf("case 2\n")
		rgb = {0, C, X, 0} // this case.. X is wrong
	case 3:
		rgb = {0, X, C, 0}
	case 4:
		rgb = {X, 0, C, 0}
	case 5:
		rgb = {C, 0, X, 0}
	case:
		panic("Some failure in HSV conversion")
	}
	rgb += m

	rgb[3] = hsv[3] // Alpha (0-1)
	return rgb
}
