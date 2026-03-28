package miniui

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


// Before calling app_window_setup(), the user must call
//  SDL.Init(SDL.INIT_VIDEO)
//  app.window = SDL.CreateWindow(...)
@(deferred_in = app_window_quit)
app_window_setup :: proc(app: ^App) {
	// Basic opening of the SDL window and gathering OpenGL

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
	app_framerate_control_init(app)
}


app_window_quit :: proc(app: ^App) {
	SDL.GL_DeleteContext(app.gl_context)
	SDL.DestroyWindow(app.window)
	SDL.Quit()
}


app_framerate_control_init :: proc(app: ^App) {
	app.time_frame_delta_target = 16750 * time.Microsecond
	app.time_start = time.tick_now()
}


// Call once per main application loop to limit the loop rate to what is setup
// in app_framerate_control_init()
app_framerate_control :: proc(app: ^App) {
	now: time.Tick = time.tick_now()
	elapsed := time.tick_diff(app.time_frame_start, now)

	if elapsed < app.time_frame_delta_target {
		time.accurate_sleep(app.time_frame_delta_target - elapsed)
	}

	app.time_frame_start = time.tick_now()
	app.t = cast(f32)time.duration_seconds(time.tick_diff(app.time_frame_start, app.time_start))
}


// Display and also call framerate control
app_display :: proc(app: ^App, gui: ^Gui) {

	window_width, window_height: i32
	SDL.GetWindowSize(app.window, &window_width, &window_height)
	draw_prepare(gui, window_width, window_height)

	draw(gui, context.temp_allocator)
	SDL.GL_SwapWindow(app.window)

	app_framerate_control(app)
}
