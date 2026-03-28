# miniui-odin

## Description
A small, portable, immediate-mode UI library written in Odin. (Extended from the Odin/vendor port of from [rxi/microui](https://github.com/rxi/microui).)


[**Browser Demo of Microui**](https://floooh.github.io/sokol-html5/sgl-microui-sapp.html) (rxi's microui)

## Features
* Works within a fixed-sized memory region: no additional memory is
  allocated
* Built-in controls: window, panel, button, slider, textbox, label,
  checkbox, wordwrapped text
* Easy to add custom controls
* Simple layout system

## Goals / Added Features
- [X] Image elements
- [X] Read-only mode; grey-out locked controls
- [ ] Support for more specific numeric inputs (integer, not float only)
- [ ] Window docking & tabs
- [ ] Tables
- [ ] Combined "number + label" gui element!

These maybe should be done as some other package:
- [X] Plots
- [ ] Bezier splines


## Rendering
Also added the significant feature of rendering. This library assumes you will externally setup an OpenGL context. See `project_template` to get going quickly! The library will setup shaders that it needs to, and has a new set of procedures to implement the rendering when called. Everything is now drawn as batched textured quads for performance.

## Notes
* This library assumes you are using the latest monthly build of the Odin compiler. Since Odin is still under development this means this library might break in the future. Please create an issue or PR if that happens. 

## License
This library is free software; you can redistribute it and/or modify it
under the terms of the MIT license. See [LICENSE](LICENSE) for details.
