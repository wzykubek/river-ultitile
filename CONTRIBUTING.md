# CONTRIBUTING

## Commit messages

Commit messages should start with a prefix indicating which part of the
project is affected by your change, if this a general code patch you may not
add it, followed by a one sentence summary, first word is capitalized. First
line is 50 columns long max.

Example:

    seat: Add pointer events

    Update to zig 1.0.0

You can add everything you feel need to be mentioned in the body of the
commit message, wrap lines at 72 columns.

A great guide to follow is [here].

## Patches

For patches, send a [plain text email] to my [public inbox]
[~midgard/public-inbox@lists.sr.ht] with project prefix set to `river-ultitile`:

You can configure your Git repo like so:

```bash
git config sendemail.to "~midgard/public-inbox@lists.sr.ht"
git config format.subjectPrefix "PATCH river-ultitile"
```

Some useful resources if you're not used to send patches by email:

- Using [git send-email].
- [plain text email], if you need a better email client and learn how to format your email.
- Learn [git rebase](https://git-rebase.io/).
- [pyonji](https://git.sr.ht/~emersion/pyonji), an easy-to-use CLI tool to send email patches.

`git.sr.ht` also provides a [web UI](https://man.sr.ht/git.sr.ht/#sending-patches-upstream) if you prefer.

## Issues

Questions or discussions works the same way as patches, mention the project
name in the subject. You don't need to add `PATCH` before the project name,
e.g.  `[river-ultitile] How do I do this?`

## Coding style

Follow the [zig style guide](https://ziglang.org/documentation/0.8.0/#Style-Guide).

[here]: https://gitlab.freedesktop.org/wayland/weston/-/blob/master/CONTRIBUTING.md#formatting-and-separating-commits
[public inbox]: https://lists.sr.ht/~midgard/public-inbox
[~midgard/public-inbox@lists.sr.ht]: mailto:~midgard/public-inbox@lists.sr.ht
[git send-email]: https://git-send-email.io
[plain text email]: https://useplaintext.email/
[git rebase]: https://git-rebase.io/
[web ui]: https://man.sr.ht/git.sr.ht/#sending-patches-upstream
[zig style guide]: https://ziglang.org/documentation/0.8.0/#Style-Guide
