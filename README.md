# river-ultitile

A WIP layout generator for **[river]**

_river-ultitile_ has a configurable layout. It lets you define a i3-like grid consisting of vsplits and
hsplits, and a filling pattern to decide the order in which views should be assigned in the grid.

## Building

Same requirements as **[river]**, use [zig] 0.12, if **[river]** and
_rivertile_ work on your machine you shouldn't have any problems.

Build, `e.g.`

    zig build -Doptimize=ReleaseSafe --prefix ~/.local

## Usage

`e.g.` In your **river** init (usually `$XDG_CONFIG_HOME/river/init`)

```bash
# Set the default layout generator to be river-ultitile and start it.
# River will send the process group of the init executable SIGTERM on exit.
riverctl default-layout river-ultitile
river-ultitile -outer-gaps 0 -per-tag &
```

### Configuration

Edit the file `config.zig` and recompile.

## Contributing

See [CONTRIBUTING.md]

## Thanks

Thanks to [Isaac Freund] and [Leon Henrik Plickat] for river obviously, for
rivertile, most of river-ultitile code comes from them!

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
