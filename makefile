# Read Zig version from build.zig
ZIG_VERSION != sed -nE '/const zig_major = ([0-9]+);/{N;s/.*const zig_major = ([0-9]+);(.|\n)*const zig_minor = ([0-9]+);.*/\1.\3/p}' ./build.zig
ifeq ($(ZIG_VERSION),)
$(error "Zig version not detected in build.zig")
endif

# Find specified Zig version in PATH (a bit involved to allow for arbitrary patch versions)
ZIG != bash -c 'IFS=: dirs=($$PATH); find "$${dirs[@]}" -maxdepth 1 -name "zig-$(ZIG_VERSION).*" -print -quit'
ifeq ($(ZIG),)
ZIG != command -v zig
ifeq ($(ZIG),)
$(error Neither zig-$(ZIG_VERSION).* nor zig found in PATH)
endif
ZIG_EXE_VERSION != $(ZIG) version | sed 's/^\([0-9]*\.[0-9]*\)\..*/\1/'
ifeq ($(ZIG_VERSION), $(ZIG_EXE_VERSION))
$(info Using $(ZIG) which is version $(shell $(ZIG) version))
else
$(error `zig-$(ZIG_VERSION)-*` not found in PATH and `$(ZIG)` is not a compatible version ($(ZIG_EXE_VERSION)))
endif
endif

.PHONY: build debug install run test
build: ; $(ZIG) build -Doptimize=ReleaseSafe
debug: ; $(ZIG) build -Doptimize=Debug
install: ; $(ZIG) build -Doptimize=ReleaseSafe install
test:
	$(ZIG) test src/util.zig
	$(ZIG) test src/config.zig
	$(ZIG) test src/layout.zig
