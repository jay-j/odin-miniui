Plot is a flexible and high performance plotting package in native [Odin](https://github.com/odin-lang/Odin). It may be used independently of Miniui.

## A Library, not an Engine
`Plot` doesn't take over! It is designed to be used *within* your application.
As a consequence, `Plot` itself isn't standalone.
See an minimal example application in `plot/example/plot_demo.odin`.
I typically use a `Miniui` wrapper for `Plot` to add interactivity, see `example/example.odin`.

The fundamentals: 
```odin
/* Caller: Setup OpenGL context */
plot_renderer = plt.render_init()
plot := plot_init(buff_Width=1920, buff_height=1080)
/* Caller: generate some []f32 data x and y */
sine := plt.dataset_add(&plot, x[:], y[:])
plt.draw(plot_renderer, &plot, view_width=512, view_height=512)
/* Caller: display the OpenGL framebuffer plot.framebuffer */
```

## GPU Rendering
`Plot` provides its own shaders and textures, but expects the caller to setup an OpenGL context.

## Framebuffer Ouput
`Plot` renders to a framebuffer(s), not directly to the screen.
- The caller has all the control. 
- In a GUI application, the cached framebuffer may be displayed rather than re-rendering every frame.
- A render resolution much larger than the available screen may be used if desired.


# TODO for Minimum Viable Product
- Text: axis labels, scale, title
- Legend
- Helper for conversion between pixels and coordinates
- Mark plot style (instead of just lines)
- Remove Miniui dependency from the plotting example.
