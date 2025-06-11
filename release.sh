#!/bin/sh

set -eu
cd "$(dirname "$0")"

prev_version="$(git describe --tags --abbrev=0 || echo none)"
printf 'Previous version:     %s\n' "$prev_version"
new_version="$(sed -En 's/^const version = "(.*)-dev";$/\1/p' build.zig)"
printf 'New version? (v%s) v' "$new_version"
read version
if [ -z "$version" ]; then
	version="$new_version"
fi

tagid=v"$version"
if [ "v$version" != "$prev_version" ]; then
	sed -i 's/const version = ".*";/const version = "'"$version"'";/' build.zig
	sed -i 's/\.version = ".*",/.version = "'"$version"'",/' build.zig.zon
	sed -Ei 's/(.*git clone .* -b ).*/\1'"$tagid"/ README.md
	sed -i 's/## \[Unreleased\]/&\n### Added\n### Changed\n### Deprecated\n### Removed\n### Fixed\n### Security\n\n## ['"$version"'] - '"$(date --utc +%Y-%m-%d)"'/' CHANGELOG.md
	echo; echo "Inspect CHANGELOG..."
	${EDITOR:-nano} CHANGELOG.md
	git add build.zig build.zig.zon CHANGELOG.md README.md
	git commit -m "build: Release version $version"

	echo "Creating git tag $tagid"

	sed -n '/^## \['"$version"'\]/,/^## \[/p' CHANGELOG.md | sed '1s/^.*$/Version '"$version"'\n/;/^$/d;s/^##* //;;$s/^.*$//' |
		git tag -s "$tagid" -F -

	fail() {
		git tag -d "$tagid"
		echo "Failed, remove the last commit with 'git reset --hard HEAD^'"
		exit 1
	}

	echo "Testing build"
	zig build || fail
	echo "Running tests"
	zig test src/util.zig || fail
	zig test src/config.zig || fail
	zig test src/layout.zig || fail

	sed -i 's/const version = ".*";/const version = "'"$version"'";/' build.zig

	printf 'Next version? v'
	read next_version
	sed -i 's/const version = ".*";/const version = "'"$next_version"'-dev";/' build.zig
	sed -i 's/\.version = ".*",/.version = "'"$next_version"'",/' build.zig.zon
	git add build.zig build.zig.zon
	git commit -m "build: Bump to version $next_version-dev"
	printf "\n\nRemember to 'git push origin %s'\n" "$tagid"
else
	echo "Version already created"
	exit 1
fi
