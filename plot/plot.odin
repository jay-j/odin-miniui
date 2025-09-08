package plot
import ha "./handle"
import "core:fmt"
import "core:log"
import "core:math"
import glm "core:math/linalg/glsl"
import "core:slice"
import "core:testing"
import gl "vendor:OpenGL"

PLOT_DEFAULT_COLOR_BACKGROUND :: glm.vec4{0.05, 0.05, 0.05, 1.0}
PLOT_DEFAULT_COLOR_ANNOTATION_MAJOR :: glm.vec4{0.4, 0.5, 0.4, 1.0}
PLOT_DEFAULT_COLOR_ANNOTATION_MINOR :: glm.vec4{0.2, 0.2, 0.2, 1.0}

// TODO: How to add text labels?

Plot_Scale_Mode :: enum {
	Stretched = 0,
	Isotropic,
	Manual,
}


PlotRenderer :: struct {
	program:  u32,
	uniforms: map[string]gl.Uniform_Info,
	vao:      u32,
}


Plot :: struct {
	framebuffer_dirty:      bool, // TODO: Implement flagging the framebuffer 
	framebuffer:            u32,
	framebuffer_rgb:        u32,
	framebuffer_depth:      u32,
	framebuffer_width_max:  i32,
	framebuffer_height_max: i32,
	color_background:       glm.vec4,
	color_annotation_major: glm.vec4,
	color_annotation_minor: glm.vec4,
	color_graph_default:    glm.vec4,

	// the current display portion
	range_x:                [2]f32,
	range_y:                [2]f32,
	scale_mode:             Plot_Scale_Mode,
	scale_auto_x:           bool,
	scale_auto_y:           bool,

	// Pointers (via slice) to the actual data being plotted
	// A Handle_Array is used to provide dynamic memory while being robust to
	// large addition and removals, e.g. h5explorer.
	data:                   ha.Handle_Array(Dataset, Dataset_Handle),

	// Using the same shader to draw grid elements, so we need VBOs
	vbo_grid_x:             u32,
	vbo_grid_y:             u32,
}


Dataset_Handle :: distinct ha.Handle
Dataset :: struct {
	handle: Dataset_Handle,
	x:      []f32,
	y:      []f32,
	color:  glm.vec4,
	vbo_x:  u32,
	vbo_y:  u32,
	// TODO: is it more performant to cache max/min or to compute on demand?
}


// STEP 1: Setup the shader to draw Plots.
// One PlotRenderer can (and usually should) be used for all plots in a program.
// ASSUME: The caller has already setup an OpenGL context.
render_init :: proc(allocator := context.allocator) -> (rend: ^PlotRenderer) {
	context.allocator = allocator

	rend = new(PlotRenderer)

	program_ok: bool
	rend.program, program_ok = gl.load_shaders_source(shader_line_vertex, shader_line_fragment)
	if !program_ok {
		panic("failed to create GLSL program for Plot rendering.")
	}
	gl.UseProgram(rend.program)

	rend.uniforms = gl.get_uniforms_from_program(rend.program)

	gl.GenVertexArrays(1, &rend.vao)

	return rend
}


// STEP 2: Create a Plot and GPU Framebuffer
// Sets up a framebuffer of dimensions (width, height). The end user's screen resolution is a
// good default, but some situations may call for larger (extra high res image export),
// or smaller (performance when displaying many plots) framebuffer dimensions.
// Since this proc is calling GPU setup and allocations, it is recommended to do this (once)
// during setup; not every frame.
plot_init :: proc(buff_width, buff_height: i32, color_background := PLOT_DEFAULT_COLOR_BACKGROUND) -> (plot: Plot) {

	// CAUTION: These dynamic arrays are allocated and expanding on the default allocator
	ha.init(&plot.data)

	plot.color_background = color_background
	plot.color_annotation_major = PLOT_DEFAULT_COLOR_ANNOTATION_MAJOR
	plot.color_annotation_minor = PLOT_DEFAULT_COLOR_ANNOTATION_MINOR

	gl.CreateFramebuffers(1, &plot.framebuffer)
	log.debugf("Created framebuffer: %v", gl.GetError())

	plot.framebuffer_width_max = buff_width
	plot.framebuffer_height_max = buff_height

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

	// Create the vertex buffers for the grid/ui stuff
	gl.GenBuffers(1, &plot.vbo_grid_x)
	gl.GenBuffers(1, &plot.vbo_grid_y)

	plot.color_graph_default = {0, 0.9, 0.9, 1.0}

	return plot
}


// STEP 3: Create a Dataset to be plotted, and send the data to the GPU.
// NOTE: The Dataset does not make or retain a CPU-side copy of the data.
dataset_add :: proc(plot: ^Plot, x, y: []f32, color := glm.vec4{0.0, 0.0, 0.0, -1}) -> Dataset_Handle {
	// TODO: how does this work if there isn't data available yet? 
	dataset := Dataset {
		x = x[:],
		y = y[:],
	}

	gl.GenBuffers(1, &dataset.vbo_x)
	gl.GenBuffers(1, &dataset.vbo_y)

	// If no color is given use a default changing value
	if color.a == -1 {
		dataset.color = plot.color_graph_default

		// Auto-increment the default color in HSV space
		plot.color_graph_default = hue_increment(plot.color_graph_default)
	} else {
		dataset.color = color
	}

	dataset_update(&dataset, x, y)

	dh := ha.add(&plot.data, dataset)

	return dh
}

// TODO set of procedures to call to change plot pan & zoom
// have the user implement how these get called

// Update pointers to CPU data, and send data to the GPU
dataset_update :: proc {
	dataset_update_ptr,
	dataset_update_handle,
}


dataset_update_ptr :: proc(dset: ^Dataset, x, y: []f32) {
	assert(len(x) == len(y))
	dset.x = x
	dset.y = y
	gl.BindBuffer(gl.ARRAY_BUFFER, dset.vbo_x)
	gl.BufferData(gl.ARRAY_BUFFER, len(x) * size_of(x[0]), &x[0], gl.STATIC_DRAW)
	gl.BindBuffer(gl.ARRAY_BUFFER, dset.vbo_y)
	gl.BufferData(gl.ARRAY_BUFFER, len(y) * size_of(y[0]), &y[0], gl.STATIC_DRAW)
}


dataset_update_handle :: proc(plot: ^Plot, dset_handle: Dataset_Handle, x, y: []f32) {
	ptr := ha.get_ptr(plot.data, dset_handle)
	dataset_update_ptr(ptr, x[:], y[:])
}


scale_auto_x :: proc(plot: ^Plot) {
	low: f32 = max(f32)
	high: f32 = min(f32)

	// Iterate through every dataset
	dataset_iter := ha.make_iter(plot.data)

	for dataset in ha.iter_ptr(&dataset_iter) {
		low = min(low, slice.min(dataset.x[:]))
		high = max(high, slice.max(dataset.x[:]))
	}
	plot.range_x = {low, high}
}


scale_auto_y :: proc(plot: ^Plot) {
	low: f32 = max(f32)
	high: f32 = min(f32)

	// Iterate through every dataset
	dataset_iter := ha.make_iter(plot.data)

	for dataset in ha.iter_ptr(&dataset_iter) {
		low = min(low, slice.min(dataset.y[:]))
		high = max(high, slice.max(dataset.y[:]))
	}
	plot.range_y = {low, high}
}


// STEP 4: Render the Plot to its framebuffer
// Displaying the framebuffer is left to the user. Note that this only needs to be
// called again if something in the plot has changed; otherwise the framebuffer can just
// be displayed again.
draw :: proc(rend: ^PlotRenderer, plot: ^Plot, view_width, view_height: i32, grid: bool = true) {

	if plot.range_x[0] == 0 && plot.range_x[1] == 0 {
		scale_auto_x(plot)
		scale_auto_y(plot)
	}

	gl.UseProgram(rend.program)

	gl.BindFramebuffer(gl.FRAMEBUFFER, plot.framebuffer)
	gl.Viewport(0, 0, view_width, view_height)
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
			ar_pixels := f32(view_width) / f32(view_height) // aspect ratio of the available pixels
			ar_data: f32 = (plot.range_x[1] - plot.range_x[0]) / (plot.range_y[1] - plot.range_y[0])

			// if data is wider than the display, use the data to set the pixel ratio width and there is extra empty height
			if ar_data >= ar_pixels {
				ratio := (plot.range_x[1] - plot.range_x[0]) / f32(view_width) // unit per pixel
				half_height := 0.5 * f32(view_height) * ratio
				average_height: f32 = 0.5 * (plot.range_y[0] + plot.range_y[1])

				copy(grid_bounds_x[:], plot.range_x[:])
				grid_bounds_y = {average_height - half_height, average_height + half_height}

				proj = glm.mat4Ortho3d(plot.range_x[0], plot.range_x[1], grid_bounds_y[0], grid_bounds_y[1], 0, 1)


			} else {
				// if data is taller than the display, use the data to set the height and there is extra empty width
				ratio := (plot.range_y[1] - plot.range_y[0]) / f32(view_height)
				half_width := 0.5 * f32(view_width) * ratio
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

	// OpenGL camera space goes from z=0 (near camera) to -1 (far from camera)
	dz: f32 = 1.0 / (3 + f32(plot.data.num))
	z: f32 = -1 + dz

	if grid {
		draw_grid(rend, plot, grid_bounds_x, grid_bounds_y, dz)
		z += 2 * dz
	}

	dataset_iter := ha.make_iter(plot.data)

	for dataset in ha.iter_ptr(&dataset_iter) {
		// set color uniform
		gl.Uniform4fv(rend.uniforms["color"].location, 1, &dataset.color[0])
		gl.Uniform1f(rend.uniforms["z"].location, z)
		z += dz

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

	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
}


draw_grid :: proc(rend: ^PlotRenderer, plot: ^Plot, grid_bounds_x, grid_bounds_y: [2]f32, dz: f32) {
	// PERFORMANCE: only if the view has changed?
	// TODO: Scale labels
	zdepth: f32 = -1.0

	grid_x := make([dynamic]f32, 0, 60, context.temp_allocator)
	grid_y := make([dynamic]f32, 0, 60, context.temp_allocator)

	// Add the grid geometry to the array
	{
		origin_x := []f32{grid_bounds_x[0], grid_bounds_x[1], 0, 0}
		append(&grid_x, ..origin_x[:])
		origin_y := []f32{0, 0, grid_bounds_y[0], grid_bounds_y[1]}
		append(&grid_y, ..origin_y[:])
	}
	calculate_grid(grid_bounds_x, grid_bounds_y, &grid_x, &grid_y)
	calculate_grid(grid_bounds_y, grid_bounds_x, &grid_y, &grid_x)

	// Upload vertices to draw, to be used for both sets of draw calls
	gl.BindBuffer(gl.ARRAY_BUFFER, plot.vbo_grid_x)
	gl.BufferData(gl.ARRAY_BUFFER, len(grid_x) * size_of(grid_x[0]), &grid_x[0], gl.STATIC_DRAW)
	gl.VertexAttribPointer(0, 1, gl.FLOAT, false, 0, uintptr(0))
	gl.EnableVertexAttribArray(0)

	gl.BindBuffer(gl.ARRAY_BUFFER, plot.vbo_grid_y)
	gl.BufferData(gl.ARRAY_BUFFER, len(grid_y) * size_of(grid_y[0]), &grid_y[0], gl.STATIC_DRAW)
	gl.VertexAttribPointer(1, 1, gl.FLOAT, false, 0, uintptr(0))
	gl.EnableVertexAttribArray(1)

	{
		// Draw minor lines / full grid
		zdepth += dz
		gl.Uniform1f(rend.uniforms["z"].location, zdepth)
		gl.Uniform4fv(rend.uniforms["color"].location, 1, &plot.color_annotation_minor[0])

		// HACK: Hardcoded the origin mark is the first 4 vertices
		gl.DrawArrays(gl.LINES, 4, cast(i32)len(grid_x) - 4)
	}

	// Draw major lines over top
	{
		zdepth += dz
		gl.Uniform1f(rend.uniforms["z"].location, zdepth)
		gl.Uniform4fv(rend.uniforms["color"].location, 1, &plot.color_annotation_major[0])
		// HACK: Hardcoded the origin mark is the first 4 vertices
		gl.DrawArrays(gl.LINES, 0, 4)
	}
}


// Given the current view bounds, calculate where the grid lines should be and append verticies to the draw lists.
calculate_grid :: proc(bounds: [2]f32, bounds_static: [2]f32, draw_inc: ^[dynamic]f32, draw_static: ^[dynamic]f32) -> (inc: f32) {
	// TODO: Manually specified grid increment
	// TODO: Responsive to the number of pixels used to render the plot
	range := bounds[1] - bounds[0]

	// Power of 10 increments one order of magnitude smaller than the displayed range.
	inc = math.pow(10, math.floor(math.log10(range) - 1))

	// Calculate the first grid line, round down to the nearest increment
	// then add until past the max bounds.
	grid_first := math.floor(bounds[0] / inc) * inc
	for x := grid_first; x < bounds[1]; x += inc {
		append(draw_inc, x)
		append(draw_inc, x)
		append(draw_static, bounds_static[0])
		append(draw_static, bounds_static[1])
	}

	return
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
	// Takes hue 0-1
	h := hsv[0]
	s := hsv[1]
	v := hsv[2]

	if s == 0 {
		rgb = {v, v, v, hsv[3]}
		return
	}

	h *= 6 // normalize to [0, 6]
	i := int(math.floor(h))
	f := h - f32(i)
	p := v * (1.0 - s)
	q := v * (1.0 - s * f)
	t := v * (1.0 - s * (1.0 - f))


	switch i {
	case 0:
		rgb = {v, t, p, 0}
	case 1:
		rgb = {q, v, p, 0}
	case 2:
		rgb = {p, v, t, 0}
	case 3:
		rgb = {p, q, v, 0}
	case 4:
		rgb = {t, p, v, 0}
	case 5:
		rgb = {v, p, q, 0}
	case:
		panic("Some failure in HSV conversion")
	}

	rgb[3] = hsv[3] // Alpha (0-1)
	return rgb
}


// Increment the hue of a color. The default increment of 0.37 is selected to
// generate a series of colors that are generally distinct.
hue_increment :: proc(rgb_in: glm.vec4, inc: f32 = 0.37) -> glm.vec4 {
	hsv := rgb_to_hsv(rgb_in)
	hsv[0] += inc
	if hsv[0] > 1.0 {
		hsv[0] -= 1.0
	}
	rgb_out := hsv_to_rgb(hsv)
	return rgb_out
}
