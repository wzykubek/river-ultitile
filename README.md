# river-ultitile

A layout generator for **[river]**

_river-ultitile_ has a configurable layout. It lets you define an i3-like grid consisting of vsplits and
hsplits, and configure the order in which views should be assigned in the grid.

## Building

Same requirements as **[river]**, use [Zig] 0.12, if **[river]** and
_rivertile_ work on your machine you shouldn't have any problems.

Build, `e.g.`

    zig build -Doptimize=ReleaseSafe --prefix ~/.local

## Usage and configuration

In your **river** init (usually `$XDG_CONFIG_HOME/river/init`), start river-ultitile (snippet below).

Configuration happens by sending commands to a running river-ultitile instance. With these commands
you build a grid of nested tiles, which can be nested arbitrarily deep. Certain tiles should be
designated to hold views; this can be done by either setting an `order` (as explained below) or
setting their `max_views` to `unlimited` or a non-zero number.

Tiles can have their contents arranged horizontally (`type=hsplit`), vertically
(`type=vsplit`), or superimposed (`type=overlay`).

Views are assigned to tiles in an order determined by the `order` property of the tiles. The
assignment of views starts with the lower orders, so lower orders get the views on the top of the
river view stack. Tiles with the same `order` will share the assigned views evenly. Use `suborder`
to determine views higher on the stack will come. Having tiles with the same `order` and `suborder`
and a non-zero `max_views` is not allowed.

Per-output or per-tag configuration is not yet possible.

The commands are as follows:
- `new layout <layoutname> [properties for root tile]…`
- `new tile <layoutname>.<tilename>[.<tilename>]… [properties]…`
- `edit <layoutname>[.<tilename>]… [properties]…`
- `default layout <layoutname>`: set the named layout as default for all outputs

Tile properties are:
- `type=<hsplit|vsplit|overlay>` (default `hsplit`)
- `padding=<number|inherit>` (default `inherit`): space around the tile's 
- `margin=<number>` (default `0`): space around the tile
- `stretch=<number>` (default `100`): a relative width specifier. The stretches of a tile's
    subtiles are summed, and the subtiles get a width proportional to their stretch divided by that
    sum. Views always have a stretch of 100.
- `order=<number>` (default `0`): see above. Setting `order` also sets `max_views=unlimited` if
    `max_views` is `0`.
- `suborder=<number>` (default `0`): see above. Setting `suborder` also sets `max_views=unlimited`
    if `max_views` is `0`.
- `max_views=<number|unlimited>` (default `0`): the maximum amount of views that will be assigned

```bash
riverctl map normal $mod K focus-view previous
riverctl map normal $mod J focus-view next
riverctl map normal $mod Z zoom
# Rest of river configuration...

# Set the default layout generator to be river-ultitile and start it.
# River will send the process group of the init executable SIGTERM on exit.
riverctl default-layout river-ultitile
river-ultitile &

ultitile() {
	riverctl send-layout-command river-ultitile "$*"
}
ultitile new layout hstack type=hsplit padding=5 margin=5 max_views=unlimited

ultitile new layout main-left type=hsplit padding=5 margin=5
ultitile new tile main-left.left type=vsplit stretch=40 order=1
ultitile new tile main-left.main type=vsplit stretch=60 order=0 max_views=1

ultitile new layout main-center type=hsplit padding=5 margin=5
ultitile new tile main-center.left type=vsplit stretch=25 order=1 suborder=0
ultitile new tile main-center.main type=vsplit stretch=50 order=0 max_views=1
ultitile new tile main-center.right type=vsplit stretch=25 order=1 suborder=1

ultitile new layout monocle type=overlay max_views=unlimited

ultitile default layout main-center

# Mod+U and Mod+I to increase/decrease the main size
riverctl map normal $mod U send-layout-cmd river-ultitile "edit main-center.main stretch+5"
riverctl map normal $mod I send-layout-cmd river-ultitile "edit main-center.main stretch-5"

# Mod+Shift+U and Mod+Shift+I to decrease/increase the main count
riverctl map normal $mod+Shift U send-layout-cmd river-ultitile "edit main-center.main max_views-1"
riverctl map normal $mod+Shift I send-layout-cmd river-ultitile "edit main-center.main max_views+1"
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
