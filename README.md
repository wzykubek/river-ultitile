# river-ultitile

A layout generator for **[river]**

_river-ultitile_ has a configurable layout. It lets you define an i3-like grid consisting of vsplits and
hsplits, and configure the order in which views should be assigned in the grid.

## Building

Same requirements as **[river]**, use [Zig] 0.12, if **[river]** and
_rivertile_ work on your machine you shouldn't have any problems.

Build with e.g.

    zig build -Doptimize=ReleaseSafe --prefix ~/.local

## Configuration

In your **river** init (usually `$XDG_CONFIG_HOME/river/init`), start river-ultitile (snippet below).

Configuration happens by modifying `src/user_config.zig` and recompiling. The default configuration
provides these layouts, that can be chosen at runtime (see snippet below):
- dwm-like main/stack layout that puts the main view in the center on wide displays and on
  the left on narrower ones,
- a vertical stack,
- a horizontal stack, and
- a monocle layout.

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

```bash
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

# By default, variables are local to the output+tag combination. If you want to set a
# variable globally, use e.g. "set global string layout = main", but note that local variable
# values will take precedence. A local variable for the current output+tag can be removed with e.g.
# "clear-local layout" (for the variable named "layout") and a all local values for a variable can
# be cleared with "clear-all-local layout".
```

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

[river]: https://codeberg.org/river/river
[zig]: https://ziglang.org/download/
[contributing.md]: CONTRIBUTING.md
[isaac freund]: https://codeberg.org/ifreund
[leon henrik plickat]: https://sr.ht/~leon_plickat/
[rivercarro]: https://sr.ht/~novakane/rivercarro/
[hugo machet]: https://sr.ht/~novakane/
[gnu general public license v3.0 or later]: COPYING
