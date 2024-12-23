# river-ultitile

A layout generator for **[river]**. Features include:  
- **configurable** layouts employing nested tiles (no juggling with coordinates),  
- **widescreen** support by default,  
- default layouts, switchable at run time with a command or key binding:  
    - dwm-like main/stack layout,  
        - main on the left on normal screens,
        - **main in the center and stacks on both sides** on widescreens,
    - a vertical stack,  
    - a horizontal stack, and  
    - a monocle layout,
- optional per-tag-per-output state.

## Building

Requirements:
- [Zig] 0.12
- [wayland-protocols]

Download the sources with

    git clone https://git.sr.ht/~midgard/river-ultitile -b v1.1.1

Build with e.g.

    cd river-ultitile
    zig build -Doptimize=ReleaseSafe --prefix ~/.local

And make sure ~/.local/bin is in your path.

## Quick start
Integrate the [snippet](#Example_river_init_file) into your river init file and look at the key
bindings it defines.

## Usage and configuration
Configuration of layouts happens by modifying `src/user_config.zig` and recompiling (see
[Configuring layouts](#Configuring_layouts) below). Layouts can use parameters that can be modified
at runtime (see [Modifying parameters](#Modifying_parameters) below).

Any error messages will appear in the stderr of **river**, so if your configuration isn't working as
expected, look there.

### Example **river** init file snippet
This snippet can be integrated in your **river** init file (usually `$XDG_CONFIG_HOME/river/init`).

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
# Increase/decrease the main size
riverctl map normal $mod U send-layout-cmd river-ultitile "set integer main-size += 4"
riverctl map normal $mod I send-layout-cmd river-ultitile "set integer main-size -= 4"

# Decrease/increase the main size if it is in the center (on widescreens)
riverctl map normal $mod+Shift U send-layout-cmd river-ultitile "set integer main-size-if-only-centered-main += 4"
riverctl map normal $mod+Shift I send-layout-cmd river-ultitile "set integer main-size-if-only-centered-main -= 4"

# Decrease/increase the main count
riverctl map normal $mod N send-layout-cmd river-ultitile "set integer main-count += 1"
riverctl map normal $mod M send-layout-cmd river-ultitile "set integer main-count -= 1"

# Change layout
riverctl map normal $mod Up    send-layout-cmd river-ultitile "set string layout = vstack"
riverctl map normal $mod Right send-layout-cmd river-ultitile "set string layout = hstack"
riverctl map normal $mod Down  send-layout-cmd river-ultitile "set string layout = monocle"
riverctl map normal $mod Left  send-layout-cmd river-ultitile "set string layout = main"

# Cycle through layouts on all tags/outputs
riverctl map normal $mod E spawn "riverctl send-layout-cmd river-ultitile 'unset-all-local layout'; riverctl send-layout-cmd river-ultitile 'set global string layout @ main hstack vstack'"
```

### Running **river-ultitile**
In your **river** init file, start **river-ultitile** as a background process.

### Modifying parameters
To change the parameters that are used in the configuration, one sends commands to **river-ultitile**
using `riverctl send-layout-cmd river-ultitile "<command>"`, where `<command>` takes one of the
following forms:

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
[wayland-protocols]: https://gitlab.freedesktop.org/wayland/wayland-protocols
[contributing.md]: CONTRIBUTING.md
[isaac freund]: https://codeberg.org/ifreund
[leon henrik plickat]: https://sr.ht/~leon_plickat/
[rivercarro]: https://sr.ht/~novakane/rivercarro/
[hugo machet]: https://sr.ht/~novakane/
[gnu general public license v3.0 or later]: COPYING
