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
[X] Image elements
[ ] Read-only mode; grey-out locked controls
[ ] Support for more specific numeric inputs (integer, not float only)
[ ] Window docking & tabs
[ ] Tables
[ ] Combined "number + label" guie element!

These maybe should be done as some other package:
[ ] Plots
[ ] Bezier splines


## Rendering
Also added the significant feature of rendering. This library assumes you will externally setup an OpenGL context. The library will setup shaders that it needs to, and has a new set of procedures to implement the rendering when called. The rendering makes a lot of `gl.Scissor()` and `gl.Clear()` calls for pixel-perfect rectangles rather than drawing quads; performance could be probably improved by changing all these to drawn quads. Text, icons, and images are already drawn as quads.

## Notes
* This library assumes you are using the latest nightly build or GitHub master of the Odin compiler. Since Odin is still under development this means this library might break in the future. Please create an issue or PR if that happens. 
* The library expects the user to provide input and handle the resultant
  drawing commands, it does not do any drawing itself.

## License
This library is free software; you can redistribute it and/or modify it
under the terms of the MIT license. See [LICENSE](LICENSE) for details.
