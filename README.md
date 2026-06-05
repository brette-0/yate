# Yet another Tile Editor

> written in `c3` for arch linux x64 amd

Controls:
- Select tile to edit (Left Mouse Click)
- Clear non-clear tile (middle mouse click)
- Remove empty tile entirely (middle mouse click)
- Select tiles for copy-paste (left shift + left click)
- Deselect selected tile for copy-paste (left shift + left click)
- Increase size of view cursor (mouse wheel up)
- Decrease size of view cursor (mouse wheel down)
- Scroll view (use mouse left on scroll bar)
- Cut selected tiles (after using left shift + left click, use ctrl + x)
- Copy selected tiles (after using shift shift + left click, use ctrl + c)
- paste selected tiles (ctrl + v, for cuts may paste once, for copies may paste many)
- Undo (ctrl + z, may be done once)
- Redo (ctrl + y, may be done once)
- Select Palette (left click on the palette, they are in squares)
- select palette id (left click on the smaller square in the bigger square)
- change colour of index of a palette (once the id is selected, use the left click on the colour you want)
- Rotate the shape in the edit window (left click 'R' on the side bar or press the 'R' key)
- flip the shape down the horizontal in the edit window (left click 'Y' on the side bar or press the 'Y' key)
- flip the shape down the vertical in the edit window (left click 'X' on the side bar or press the 'X' key)
- Toggle On/Off Grid in the editor (left click 'G' on the side bar or press the 'G' key)
- switch to 'draw' tool to draw free hand (left click 'D' on the side bar or press the 'D' key)
- switch to 'fill' tool to fill an area (left click 'F' on the side bar or press the 'F' key)
- switch to 'square' tool to draw a square (left click 'S' on the side bar or press the 'S' key)
- switch to 'circle' tool to draw a circle (left click 'C' on the side bar or press the 'C' key)
- select pixels in editor to copy and paste (left shift + left click to create shape and anchor)
- copy and paste pixels to elsewhere in edit (ctrl + c, then ctrl + v)
- set specifical scale of application (ctrl + 1, ctrl + 2 ... but may elect to maximum visible if monitor is too small)

Actions:
- `new` creates a new file using the OS file manager
- `open` erases the current context to load a new graphic file, failing if invalid
- `save` immediately replaces the file opened with the latest modifications
- `trim lead` removes all leading whitespace tiles 
- `trim tail` removes all trailling whitespace tiles
- `shrink` removes all whitespaces tiles, unless all are whitespace, in which case one remains
- `compress` exports an `rle` compression of the graphics for `chr-ram` use.
- `scale Nx` changes the scale of the window, because kde and glfw have disagreements on resize rules.
