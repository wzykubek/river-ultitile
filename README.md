# river-ultitile

A layout generator for **[river]**

_river-ultitile_ has a configurable layout. It lets you define an i3-like grid consisting of vsplits and
hsplits, and configure the order in which views should be assigned in the grid.

The default configuration provides these layouts, that can be chosen at runtime (see the
[river init file snippet](#Example_river_init_file)):  
- dwm-like main/stack layout that puts the main view in the center on wide displays and on
  the left on narrower ones,  
- a vertical stack,  
- a horizontal stack, and  
- a monocle layout.

## Building

Same requirements as **river**, use [Zig] 0.12, if **river** and
_rivertile_ work on your machine you shouldn't have any problems.

Build with e.g.

    zig build -Doptimize=ReleaseSafe --prefix ~/.local

## Usage and configuration
Configuration of layouts happens by modifying `src/user_config.zig` and recompiling. Layouts can
use parameters that can be modified at runtime.

Any error messages will appear in the stderr of **river**, so if your configuration isn't working as
expected, look there.

### Running _river-ultitile_
In your **river** init (usually `$XDG_CONFIG_HOME/river/init`), start _river-ultitile_ in the
background (see the [example init file below](#Example_river_init_file_snippet)).

### Modifying parameters
To change the parameters that are used in the configuration, one sends commands to _river-ultitile_
using `riverctl send-layout-cmd river-ultitile "<command>"`, where `<command>` is one of  
- `set [global] <variable_type> <variable_name> <operator> <value...>`  
- `unset-local <variable_name>`  
- `unset-all-local <variable_name>`

#### `set [global] <variable_type> <variable_name> <operator> <value...>`
Set the value for a parameter called `<variable_name>`.

`[global]`: By default, a parameter assignment will be bound to the current dominant tag (the
least-significant bit) of the currently focused Wayland output (monitor). Adding `global` to a
definition will instead apply to all tags of all outputs.

`<variable_type>`
- `integer` (32-bit signed integers)
- `string`
- `boolean` (either `true` or `false`)

`<operator>`
- `=` (set value, takes only one `<value>`)
- `@` (cycle between an arbitrary amount of unique values)
- For integers only: `+=`, `-=` (add and subtract from current value)

#### `unset-local <variable_name>`
Unset local assignments for `<variable_name>` for the current tags of the currently focused Wayland
output.

#### `unset-all-local <variable_name>`
Unset local assignments for `<variable_name>` for all tags of all Wayland outputs.

### Example river init file snippet
```bash
mod=Super
riverctl map normal $mod K focus-view previous
riverctl map normal $mod J focus-view next
riverctl map normal $mod Z zoom
# Rest of river configuration...

# Set the default layout generator to be river-ultitile and start it.
# River will send the process group of the init executable SIGTERM on exit.
riverctl default-layout river-ultitile
river-ultitile &

# These keybinds work with the default river-ultitile configuration
# Mod+U and Mod+I to increase/decrease the main size
riverctl map normal $mod U send-layout-cmd river-ultitile "set integer main-size += 5"
riverctl map normal $mod I send-layout-cmd river-ultitile "set integer main-size -= 5"

# Mod+Shift+U and Mod+Shift+I to decrease/increase the main count
riverctl map normal $mod+Shift U send-layout-cmd river-ultitile "set integer main-count -= 1"
riverctl map normal $mod+Shift I send-layout-cmd river-ultitile "set integer main-count += 1"

# Mod+{Up,Right,Down,Left} to change layout
riverctl map normal $mod Up    send-layout-cmd river-ultitile "set string layout = vstack"
riverctl map normal $mod Right send-layout-cmd river-ultitile "set string layout = hstack"
riverctl map normal $mod Down  send-layout-cmd river-ultitile "set string layout = monocle"
riverctl map normal $mod Left  send-layout-cmd river-ultitile "set string layout = main"

# Mod+z to change layout on all tags/outputs
riverctl map normal $mod E spawn "riverctl send-layout-cmd river-ultitile 'unset-all-local layout'; riverctl send-layout-cmd river-ultitile 'set global string layout @ main hstack vstack'"
```

### Configuring layouts
Modifying layouts is done by modifying `src/user_config.zig` and recompiling (see
[Building](#Building) above).

In the `src/user_config.zig` file, the function `layoutSpecification` should return your layout
expressed in terms of tiles which can be nested arbitrarily deep. Certain tiles should be
designated to hold views by setting their `max_views` to `null` (for unlimited) or a non-zero
number.

Tiles can have their contents arranged horizontally (`typ=.hsplit`), vertically
(`typ=.vsplit`), or superimposed (`typ=.overlay`).

Views are assigned to tiles in an order determined by the `order` property of the tiles. The
assignment of views starts with the lower orders, so lower orders get the views on the top of the
river view stack. Tiles with the same `order` will share the assigned views evenly. Use `suborder`
to determine views higher on the stack will come. Having tiles with the same `order` and `suborder`
and a non-zero `max_views` is not allowed.

Tile properties are:  
- `typ=<.hsplit|.vsplit|.overlay>` (default `.hsplit`)  
- `padding=<number|null>` (default `null`; `null` means inherit)): space around the tile's contents  
- `margin=<number>` (default `0`): space around the tile  
- `stretch=<number>` (default `100`): a relative width specifier. The stretches of a tile's
    subtiles are summed, and the subtiles get a width proportional to their stretch divided by that
    sum. Views always have a stretch of 100.  
- `order=<number>` (default `0`): see above  
- `suborder=<number>` (default `0`): see above  
- `max_views=<number|null>` (default `0`; `null` means unlimited): the maximum amount of views that
  will be assigned to this tile

## Contributing

See [CONTRIBUTING.md]

## Thanks

Thanks to [Isaac Freund] and [Leon Henrik Plickat] for river obviously!

Thanks to [Hugo Machet] for [rivercarro], from which river-ultitile is forked!

## License

river-ultitile is licensed under the [GNU General Public License v3.0 or later]

Files in `common/` and `protocol/` directories are released under various
licenses by various parties. You should refer to the copyright block of each
files for the licensing information.

## URLs
Project homepage: https://sr.ht/~midgard/river-ultitile/

[river]: https://codeberg.org/river/river
[zig]: https://ziglang.org/download/
[contributing.md]: CONTRIBUTING.md
[isaac freund]: https://codeberg.org/ifreund
[leon henrik plickat]: https://sr.ht/~leon_plickat/
[rivercarro]: https://sr.ht/~novakane/rivercarro/
[hugo machet]: https://sr.ht/~novakane/
[gnu general public license v3.0 or later]: COPYING
