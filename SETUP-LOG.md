# Setup log

Running record of every step taken outside this repo (system config, `/etc/portage`
changes, decisions made along the way) while building the Gentoo packaging for the
v2 WM stack. The repo itself (ebuilds, configs) is self-documenting via git history;
this file exists for the parts that *aren't* in the repo — system state you'd
otherwise have to reconstruct from scrollback.

## System changes made so far

All of these were applied by you, via sudo, running scripts I generated into the
scratchpad — this file is the durable record of what they did.

1. **Registered the local overlay** — `/etc/portage/repos.conf/loupax-wm.conf`
   points Portage at `~/src/dotfiles-v2/overlays/gentoo`.

2. **Unmasked the live ebuilds** — `/etc/portage/package.accept_keywords/loupax-wm`
   accepts `**` for `gui-wm/dwl`, `gui-apps/somebar`, `gui-apps/someblocks`,
   `gui-apps/tofi`, `gui-apps/waylock`, `gui-apps/wlopm` (all `-9999` live ebuilds,
   so they carry no stable keywords by design).

3. **USE flag adjustments** — `/etc/portage/package.use/loupax-wm`:
   - `media-libs/freetype harfbuzz` — required by `pango`, pulled in by `somebar`'s
     text rendering.
   - `gui-wm/dwl::loupax-wm X` — enables dwl's optional Xwayland support (kept
     narrow/opt-in rather than a global `X` flag, see below).
   - `gui-libs/wlroots X` — wlroots' own Xwayland-embedding support, required
     when dwl is built with `X`.

4. **Preferred prebuilt zig** — `/etc/portage/package.mask/loupax-wm` masks
   `dev-lang/zig:0.15` (source build), so the `|| ( dev-lang/zig dev-lang/zig-bin )`
   dependency in `waylock`'s build falls back to `dev-lang/zig-bin-0.15.1`
   (prebuilt, stable-keyworded amd64). Without this, emerge would build `zig` from
   source together with a full LLVM-20 toolchain (clang, compiler-rt, lld, openmp)
   just to get a Zig compiler for one small binary — avoidable.

5. **Enabled `wayland` globally** in `/etc/portage/make.conf`'s `USE` line. This
   machine was a fresh Gentoo install never configured for desktop use — the
   default `USE` had `-X -gtk -gnome -kde -qt5 -qt6 -wayland -systemd`. `wayland`
   is foundational for basically everything in this stack (mesa's EGL wayland
   platform, etc.), so it went in globally. `X` was deliberately **not** flipped
   globally — kept scoped to just `gui-wm/dwl` (see #3), matching the plan's
   "Wayland-native WM stack, X11 only where explicitly needed" design. `gtk`,
   `gnome`, `kde`, `qt5`, `qt6`, `systemd` were left untouched — out of scope for
   this work.

6. **`media-libs/mesa`, `media-libs/libepoxy`, `media-libs/libglvnd`** all
   needed `X` too (added to `/etc/portage/package.use/loupax-wm`) — Xwayland's
   accelerated rendering path goes through GLX, which needs these built with
   X11 support even though the WM stack itself is Wayland-only.

7. **Set `VIDEO_CARDS="amdgpu radeonsi"`** in `/etc/portage/make.conf` (was
   empty — another artifact of the fresh install). Without it, mesa builds with
   no hardware GPU driver at all, only software rendering (llvmpipe). The
   laptop has an AMD Radeon Vega integrated GPU (GCN 5th-gen). Gentoo splits
   AMD GPU support across two separate `VIDEO_CARDS` tokens: `amdgpu` is the
   kernel DRM driver name (used by `libdrm`/`linux-firmware`), `radeonsi` is
   mesa's actual Gallium3D OpenGL/Vulkan driver for GCN+ chips — both are
   required; setting only `amdgpu` (as done first, then corrected) leaves
   mesa's `radeonsi` flag off and you get software rendering anyway.

## Bugs found and fixed along the way

- **wlroots dependency split across two slots.** `dwl`'s original ebuild wrote
  the wlroots dependency as two separate atoms:
  ```
  >=gui-libs/wlroots-0.19:=[libinput,session,X?]
  <gui-libs/wlroots-0.20:=
  ```
  Since `gui-libs/wlroots` is slotted per minor version (`0.19`, `0.20`, ...),
  Portage satisfied each atom independently — the `X?` atom via `wlroots-0.20.1`
  (which defaults to `X` on) and the version-cap atom via `wlroots-0.19.2` (`X`
  off), producing an inconsistent plan that pulled in *two* wlroots slots and a
  bogus "needs `>=gui-libs/wlroots-0.20.1 X`" suggestion that would have
  conflicted with dwl's own actual build (which links against 0.19 specifically
  via `pkg-config wlroots-0.19`). Fixed by pinning the slot directly in one atom:
  `>=gui-libs/wlroots-0.19:0.19=[libinput,session,X?]`. See
  `packages/dwl/packaging/gentoo/dwl-9999.ebuild`.

- **wlroots fork is an unmodified mirror.** Diffed `Loupax/wlroots` against
  upstream `wlroots.org` at the same tag (`0.19.3`) — byte-identical. No custom
  ebuild needed; `dwl` just depends on stock `gui-libs/wlroots`.

## Real emerge attempt #1

Ran the real `emerge` (no `--pretend`). 41/70 packages installed fine, then
`gui-apps/wlopm-9999` failed to compile:

```
wlopm.c:27:10: fatal error: ffi.h: No such file or directory
```

Turned out to be an easter egg in `wlopm.c` — it `#include <ffi.h>` purely to
check `FFI_VERSION_NUMBER` at compile time and print a joke warning
("compiled against vibe-coded dependencies (libffi)") on newer libffi; no
libffi functions are actually called or linked. My ebuild just didn't declare
the header dependency. Fixed by adding `dev-libs/libffi` to `DEPEND` (not
`RDEPEND` — nothing is linked at runtime) in
`packages/wlopm/packaging/gentoo/wlopm-9999.ebuild`.

## Real emerge attempt #2

Ran `emerge --resume` — it failed on `wlopm` with the *exact same* `ffi.h` error,
which looked like the DEPEND fix didn't take. Root cause: `--resume` replays the
dependency-resolution job list computed *before* the ebuild fix, verbatim — it
never re-reads the (now-changed) ebuild, so `dev-libs/libffi` never entered the
job list. Lesson: after editing an ebuild mid-run, don't use `--resume` for the
next attempt — just re-run the plain `emerge <atoms>` command again. Portage
recomputes the graph from the current ebuild state and skips anything already
merged, so nothing already-installed gets rebuilt or lost.

Underneath that, there was also a real second bug: `dev-libs/libffi` turned out
to already be installed (pulled in transitively by `glib`), but the compile
still failed — Gentoo installs libffi's header to a non-standard path
(`/usr/lib64/libffi/include/ffi.h`, not the default include path), so it's
only found via `pkg-config --cflags libffi`, which wlopm's plain Makefile
doesn't do. Fixed by passing `CFLAGS="${CFLAGS} $(pkg-config --cflags libffi)"`
in `src_compile()` in
`packages/wlopm/packaging/gentoo/wlopm-9999.ebuild`.

Next step: re-run the plain (non-resume) emerge for all six atoms.

## Real emerge attempt #3

`wlopm` built successfully this time (libffi fix worked). `waylock` failed at
the fetch/verify stage instead:

```
!!! Fetched file: wayland-0.6.0-...tar.gz VERIFY FAILED!
!!! Reason: Insufficient data for checksum verification
```

Root cause: back when the ebuilds were first written, `ebuild waylock-9999.ebuild
manifest` was run as the regular user (no root), which failed silently due to
no `/var/cache/distfiles` write access (noted at the time, but the Manifest was
never actually regenerated correctly afterward) — so `waylock`'s `Manifest` file
has no checksum entries for its two vendored Zig dependency tarballs
(`zig-wayland`, `zig-xkbcommon`). Root has real distfiles access, so re-running
`ebuild waylock-9999.ebuild manifest` as root should fetch and hash them
properly this time.

## Real emerge attempt #4

Manifest fix worked (no more VERIFY FAILED). `waylock` got further this time —
past fetch, into the actual Zig compile — then failed with a real source bug:

```
build.zig:41:29: error: member function expected 0 argument(s), found 1
    const stdout = scdoc.captureStdOut(.{});
/opt/zig-bin-0.15.1/lib/std/Build/Step/Run.zig:571:5: note: function declared here
pub fn captureStdOut(run: *Run) std.Build.LazyPath
```

This is a bug in `Loupax/waylock` itself, not the ebuild or Portage: its
`build.zig` calls `captureStdOut(.{})` (passing an empty options struct), but
Zig 0.15.1's stdlib `captureStdOut` takes zero arguments — the fork's
`build.zig` was written against a different Zig std API version, despite the
repo's README claiming "Zig 0.15 compatible". Worked around at the ebuild
level with a one-line `sed` fix in `src_prepare()` in
`packages/waylock/packaging/gentoo/waylock-9999.ebuild` (removes the `.{}`
argument). **This should probably also be fixed upstream in `Loupax/waylock`
itself** — the ebuild-level patch only fixes it for this build, not for
anyone else building the fork fresh against Zig 0.15.1.

## waylock dropped from this pass

Decided to drop `waylock` from the current install for now rather than chase
it further. Worth recording *why*, since the blockers turned out to be
packaging/source bugs, not missing system infrastructure — nothing about the
system genuinely lacks what waylock needs (PAM is standard, the
ext-session-lock-v1 protocol comes from wlroots/dwl, already part of this
stack). The fix for the `build.zig` bug (see above) was in place and likely
would have gotten it building on the next attempt. Deprioritized because: (a)
it's not a dependency of anything else — dwl/somebar/someblocks/tofi/wlopm
all work without it, it's only the lock-screen keybind, (b) four rounds of
back-and-forth on one package is a good point to cut losses and get the core
stack running first. `packages/waylock/` and its ebuild stay in the repo as-is
(fix included) — revisit later by just re-running emerge for it alone. Also
worth pushing the `captureStdOut` fix upstream to `Loupax/waylock` itself at
some point (see above), independent of when we come back to packaging it.

## Real emerge attempt #5

`dwl` failed to compile against the ported `config.h`:

```
config.h:52:14: error: unknown type name 'MonitorProfile'; did you mean 'MonitorRule'?
config.h:54:18: error: unknown type name 'ProfileOutput'
```

Traced this to a divergence between two of your GitHub repos, not a v2
packaging bug: `Loupax/dotfiles` vendors a copy of dwl's source under `dwl/`
(kept in sync via `git subtree push/pull`), and at some point a change landed
in that vendored copy (the `MonitorProfile`/`ProfileOutput` auto-positioning
feature, `dwl.c:232-237` in the monorepo) that never got `git subtree push`ed
back out to the standalone `Loupax/dwl` fork — which is what v2's ebuild
actually builds from. Confirmed via a fresh clone of `Loupax/dwl`: zero
matches for either type. This environment also has no SSH key configured, so
pushing the fix to the fork wasn't an option here anyway.

Decision: drop the monitor-profiles block from `packages/dwl/config.h` for
now (back to just the static `monrules[]`, which the fork does have) rather
than push the fix from this session. Pushing the feature to `Loupax/dwl`
(via `git subtree push --prefix=dwl dwl main` from `~/src/dotfiles`, from a
machine with real push access) is a separate follow-up, independent of this
packaging work — the DP-2+eDP-1 auto-positioning behavior can come back once
that's done, just by restoring the block that was removed here.

## Real emerge attempt #6

`dwl` succeeded (monitor-profiles removal fixed it). `tofi` failed at
configure:

```
meson.build:1:0: ERROR: Value "true" (of type "string") for option "man-pages"
is not one of the choices. Possible choices are (as string): "enabled", "disabled", "auto".
```

tofi's `man-pages` meson option is a `feature` type (`enabled`/`disabled`/`auto`),
not a boolean — my ebuild passed `true`/`false`. Fixed
`-Dman-pages=$(usex man true false)` → `$(usex man enabled disabled)` in
`packages/tofi/packaging/gentoo/tofi-9999.ebuild`.

## All 5 packages installed (waylock deferred)

`emerge` succeeded for `dwl`, `somebar`, `someblocks`, `tofi`, `wlopm`. Verified
via `qlist -Iv`.

Found a follow-up bug while checking for a session launcher: `/usr/bin/startdwl`
installed as a **dangling symlink** — the fork's own `Makefile` does
`ln -sf $(CURDIR)/startdwl ...` (symlinks into the source dir rather than
copying), which only works when building in-place like v1 does; under a
packaged build the source dir is ephemeral and gets cleaned up right after
merge. Also, the script's *content* is inherently tied to the v1 monorepo
layout (`$DOTFILES/wallpaper.jpg`, `$DOTFILES/dwl/autostart.sh` relative to
itself) and calls `lock-session` (from `waylock`, deferred) and
`wl-idle-inhibit` (a separate Go tool from v1, not yet packaged in v2) — not
reusable as-is regardless of the symlink bug.

Fixed the symlink bug by removing the broken install in
`packages/dwl/packaging/gentoo/dwl-9999.ebuild`'s `src_install()`
(`rm -f "${ED}"/usr/bin/startdwl`). v2 will provide its own session launcher
separately under `configs/` rather than relying on the fork's copy — that's
the next piece of work, not yet done.

## Installing autostart.sh's supporting tools

Decided to install the remaining `autostart.sh` dependencies properly rather
than write a minimal launcher around their absence: `swaybg`, `swayidle`,
`playerctl`, `xauth`, `dbus`, `wireplumber`, `pipewire`, `slurp`, `grim`,
`swappy`, `wl-clipboard`, `libnotify`, `tmux`, `fzf`, `wf-recorder`, `swaync`.
All in the main tree except `swaync` (GURU).

- **Registered GURU** — `/etc/portage/repos.conf/guru.conf`
  (`sync-uri = https://github.com/gentoo/guru.git`), synced via
  `emaint sync --repo guru`.
- **Accepted `~amd64` keywords** (added to `/etc/portage/package.accept_keywords/loupax-wm`)
  for three packages with no stable amd64 build: `gui-apps/swaync::guru`,
  `gui-apps/wf-recorder`, `gui-libs/gtk4-layer-shell` (swaync's GTK4
  layer-shell dependency).
- **USE flags** (added to `/etc/portage/package.use/loupax-wm`):
  `gui-libs/gtk4-layer-shell introspection vala` (required by swaync),
  `media-video/ffmpeg x264` (required by wf-recorder),
  `x11-libs/gtk+ X` (required by libnotify's notification-daemon dependency).
- **Go bootstrap circular dependency**: `app-shells/fzf` is Go-based and needs
  `dev-lang/go` to build; on a system with no Go at all, Portage's solver hit
  `dev-lang/go` depending on `dev-lang/go` (buildtime) — a fresh `go` ebuild
  needs an *existing* Go compiler to bootstrap itself, and the solver didn't
  automatically pick the `dev-lang/go-bootstrap` alternative from go's own
  `|| ( >=dev-lang/go-X >=dev-lang/go-bootstrap-X )` BDEPEND. Fixed by
  explicitly emerging `dev-lang/go-bootstrap` first, which then lets the real
  `dev-lang/go` build normally.

Two more rounds on this batch:
- Tried `--exclude virtual/notification-daemon` to skip libnotify's soft
  `PDEPEND` on a notification daemon (since `swaync` is our real one) — this
  backfired: `--exclude` masks the package outright rather than skipping it
  gracefully, and it turned out moot anyway, since `swappy` (screenshot
  annotation, already in `dwl-config.h`'s keybinds) needs `gtk+[X]`/`cairo[X]`
  directly for its own UI regardless of libnotify's PDEPEND. Reverted the
  exclude, added `x11-libs/cairo X` to `/etc/portage/package.use/loupax-wm`
  instead — resolves cleanly.

Final dry-run: **75 packages, 217MB, no masks, no USE conflicts.**

Real emerge succeeded — all 16 packages installed cleanly, verified via
`qlist -Iv`. Everything `autostart.sh` needs is now present: `swaybg`,
`swayidle`, `playerctl`, `xauth`, `dbus`, `wireplumber`, `pipewire`, `slurp`,
`grim`, `swappy`, `wl-clipboard`, `libnotify`, `tmux`, `fzf`, `wf-recorder`,
`swaync`.

## v2 session launcher

Wrote `configs/dwl/startdwl` — a self-contained replacement for v1's
`startdwl`+`autostart.sh` pair. Single file, no monorepo-relative `$DOTFILES`
path assumption (just `readlink -f "$0"` to find itself, and
`~/.config/dwl/wallpaper.jpg` for the wallpaper). Ported all of `autostart.sh`
except: the waylock-dependent idle→lock `swayidle` timer (dropped per
direction — no lock-on-idle until `waylock` is packaged) and
`idle_inhibit_when_playing`/`wl-idle-inhibit` (never part of the v2 package
set to begin with, not just deferred). Kept the `wlopm`-based display-off
idle timer since `wlopm` is installed and doesn't need waylock.

Also added `configs/dwl/dwl.desktop` (wayland-sessions entry) and
`configs/dwl/env.example` (documents the machine-local `~/.config/dwl/env`
convention from v1 — mainly the `PATH` export dwl's spawned children need to
find `~/.local/bin` scripts).

Wired everything into place on this machine:
- `~/.local/bin/{startdwl,tofi_run_history,recorder,tmux-sessionizer}` → symlinked into `dotfiles-v2/configs/`
- `~/.config/tofi` → symlinked (whole dir) to `dotfiles-v2/configs/tofi`
- `~/.local/share/wayland-sessions/dwl.desktop` → symlinked

Hit one design bug while doing this: initially symlinked the whole
`~/.config/dwl` directory into the repo, same as `tofi`'s — but `env` is
supposed to be a real, machine-local, *not-committed* file, and a directory
symlink into the repo means writing `~/.config/dwl/env` would literally write
into the git-tracked `configs/dwl/` folder. Fixed by making `~/.config/dwl`
a real directory instead, with only the tracked file (`wallpaper.jpg`)
symlinked in, and `env` copied there as a genuine local file (from
`env.example`, then editable/git-ignored from that point on).

## First successful boot

`startdwl` failed initially with a chain of environment/session-management
gaps this fresh install had never had configured (none of this is v2
packaging-specific, all system-level):

1. **`XDG_RUNTIME_DIR` unset** — no `elogind`/`systemd-logind` running on this
   OpenRC system to set it up automatically. Fixed for manual/testing runs by
   exporting it and creating `/run/user/<uid>` by hand (needs root, since
   `/run/user` itself is root-owned 0755). Note for later: a real
   login-manager-driven session still needs this solved properly (`elogind`
   + PAM, or baked into a shell profile).
2. **`/run/user/1001` owned by root** — first manual creation attempt ran as
   root; fixed ownership to `loupax:loupax`, mode `0700`.
3. **No seat/session backend running at all** — `sys-auth/seatd` had been
   pulled in as a `gui-libs/wlroots[session]` dependency, but only the
   `libseat` *client* library was installed; the actual `seatd` *daemon* was
   never built because `USE="-server"` (default-off). Considered the
   alternative (udev rules granting `video`/`input` group direct device
   access, no daemon at all) but decided to finish `seatd` instead — already
   most of the way there, and it's the standard path `wlroots`'s `session`
   USE flag is designed around. Fixed: added `sys-auth/seatd server` to
   `/etc/portage/package.use/loupax-wm`, re-emerged (now installs
   `/usr/bin/seatd` + `/etc/init.d/seatd` + creates an `acct-group/seat`
   group), added `loupax` to the `seat` group, `rc-update add seatd default`,
   `rc-service seatd start`.
4. **Group membership doesn't apply to an already-open session** — had to
   start a genuinely fresh login (switched to a free TTY via Ctrl+Alt+F3)
   for the new `seat` group membership to take effect; the existing
   SSH/tmux session never picked it up.

With `XDG_RUNTIME_DIR` exported and `seatd` running, `startdwl` launched
successfully from a fresh TTY login.

## Wallpaper format fix

`swaybg` failed to load `wallpaper.jpg`: `Swaync was compiled without
gdk_pixbuf support so only PNG images can be loaded` (this system's
`gui-apps/swaybg` was built with `USE="-gdk-pixbuf"`, its default — no JPEG
decoding). Also caught along the way: `foot` (the terminal) had been
identified early on as "already in the tree, just emerge it" but never
actually made it into either real `emerge` invocation — installed separately.

Rather than rebuild `swaybg` with `gdk-pixbuf` (extra dependency weight for
decoding formats beyond this one static image), converted the wallpaper to
PNG instead: `configs/dwl/wallpaper.jpg` → `configs/dwl/wallpaper.png` (via
`ffmpeg`), updated the reference in `configs/dwl/startdwl`, re-symlinked
`~/.config/dwl/wallpaper.png`.

## Duplicate Xwayland fix

`Failed to bind socket @/tmp/X11-unix/X0` / `X1, address already in use`:
`startdwl` was manually launching a standalone `Xwayland :1 ...` (carried
over from v1's `autostart.sh`), but the `Loupax/dwl` fork now has its own
built-in Xwayland integration (`dwl.c:2713`, `wlr_xwayland_create(dpy,
compositor, 1)` -- lazy-spawned on first X11 client, confirmed via the
fork's `xwaylandready()` handler setting up the seat/cursor itself). Both
were racing for the same X11 socket. Removed the manual `Xwayland`/`xauth`
block from `configs/dwl/startdwl` entirely; kept a trimmed
`dbus-update-activation-environment` call for just `WAYLAND_DISPLAY`/
`XDG_CURRENT_DESKTOP` (still needed for portal/screen-share activation,
unrelated to the Xwayland conflict).

## Debugging the persisting error: stale processes, then real D-Bus gap

User kept seeing the Xwayland socket error even after the fix above. Turned
out three separate `dwl` processes were still running in the background
(PPID 1, no controlling terminal, no actual Wayland socket held — orphaned
from earlier sessions that never got cleanly killed), racing each other.
Killed all three (`kill -9`), confirmed `/tmp/.X11-unix/` and
`/run/user/1001/wayland-*` were clean.

Test-launched `startdwl` directly (myself) to get precise error text, per
request. First attempt hit `libseat: Permission denied` on `/run/seatd.sock`
— but that was specific to *my* shell having stale group membership (same
"needs a fresh login" issue as before, confirmed by checking `id` in the
user's actual TTY, which correctly showed `seat` in `groups=`). Retested
using `sg seat -c "startdwl ..."` to get correct group permissions without a
full relogin.

With that, `dwl` actually started successfully — no more Xwayland conflict,
found the `eDP-1` output, `swaybg` loaded the wallpaper correctly. New real
error: no D-Bus session bus running at all (`dbus-update-activation-environment:
unable to connect to D-Bus`, `swaync: Could not connect to DBus!`) — this
OpenRC system has no systemd/elogind session-bus autolaunch mechanism.
Fixed by wrapping the whole compositor launch in `dbus-run-session` (already
installed, part of `sys-apps/dbus`) in `configs/dwl/startdwl`'s final `exec`
line, so `dwl` and everything it spawns inherit a working
`DBUS_SESSION_BUS_ADDRESS`.

## somebar crash on VT switch

Bar disappeared every time switching away from and back to dwl's VT
(Ctrl+Alt+Fx). Diagnosed by relaunching `somebar`/`someblocks` manually with
stderr captured to a file, then reproducing: `somebar` exits with
`listener function for opcode 1 of zwlr_layer_surface_v1 is NULL` the moment
the compositor sends a `closed` event for the layer-shell surface (opcode 1),
which plausibly happens when an output gets removed/re-added around a VT
switch. `libwayland-client` fatally aborts a client that receives an event
with no listener registered for it.

Same class of bug as the `dwl` monitor-profiles gap earlier: the v1
monorepo's local copy of `somebar/src/bar.cpp` already has a `closed` handler
(calls the existing `Bar::hide()`), but it was never pushed to the actual
`Loupax/somebar` GitHub fork -- confirmed by cloning it fresh, only the
`configure` callback is registered there. Unlike the monitor-profiles gap
(a nice-to-have), this is a real crash, so patched it at the ebuild level now
rather than deferring: `packages/somebar/packaging/gentoo/somebar-9999.ebuild`
`src_prepare()` inserts the missing `closed` → `hide()` lambda into
`src/bar.cpp` via a small inline Python rewrite (the block being replaced
isn't a single line, so `sed` was awkward here). Should still be pushed
upstream to `Loupax/somebar` properly at some point, same as the dwl fix.

## Current state

Dependency graph for all six packages (`dwl`, `somebar`, `someblocks`, `tofi`,
`waylock`, `wlopm`) resolves cleanly via `emerge --pretend` — no USE conflicts,
no cross-slot splits, hardware-accelerated rendering (`radeonsi`/`amdgpu`) will
actually get built. **70 packages, ~390MB downloads.** Nothing has actually been
installed yet — every step so far has been dry-run validation
(`emerge --pretend`) plus the `/etc/portage` config changes listed above.
`surf`/`tabbed` (X11 app layer) are out of scope for this pass per explicit
direction — descoped, not forgotten.

**Next step**: a real `emerge` of the six packages (no `--pretend`). This is the
first step that actually installs anything / compiles LLVM 22 + mesa (the bulk
of the build time). Command, for reference:

```
emerge --verbose \
	gui-wm/dwl::loupax-wm \
	gui-apps/somebar::loupax-wm \
	gui-apps/someblocks::loupax-wm \
	gui-apps/tofi::loupax-wm \
	gui-apps/waylock::loupax-wm \
	gui-apps/wlopm::loupax-wm
```

After that, remaining work to get a usable session: symlink
`configs/tofi/config` to `~/.config/tofi/config`, install
`configs/scripts/{tofi_run_history,recorder}` and
`configs/sessionizer/tmux-sessionizer` to somewhere on `$PATH` (e.g.
`~/.local/bin`, matching how v1 did it), and write a `startdwl`-equivalent
session launcher (v1 had one baked into the `dwl` fork itself as
`dwl/startdwl` — need to confirm the Loupax fork still carries it and that it
still works with the tofi/foot swap).

## somebar VT-switch crash, actually fixed (2026-08-15)

The `closed`-event patch described above was written into
`packages/somebar/packaging/gentoo/somebar-9999.ebuild` on 2026-08-13, but the
installed `/usr/bin/somebar` was still the 2026-08-12 build — the package was
never re-emerged after the ebuild edit, so the running binary still had the
unpatched upstream listener and kept hard-aborting on every VT switch away
and back. Confirmed by comparing `qlist`/binary mtime against the ebuild's
mtime. Fixed by `emerge --oneshot gui-apps/somebar::loupax-wm`. Verified by
reproducing the VT switch after rebuilding — bar survives now.

## Sound (2026-08-15)

Asked to "enable sound." Found three separate problems:

1. A legacy `media-sound/pulseaudio-daemon` was running instead of the
   PipeWire/WirePlumber stack this repo's dependency list (see the
   `autostart.sh` porting note above) already assumed. Nothing in
   `configs/dwl/startdwl` ever actually started `pipewire`/`wireplumber` —
   they were only ever *installed*, never launched. dwl's own media keys
   (`config.h`) call `wpctl`, which only talks to PipeWire, so they were
   silently doing nothing.
2. `media-video/pipewire-1.6.7` had been built with USE=`elogind readline
   ssl` only — no `dbus`, `sound-server` (the pipewire-pulse compat server),
   `pipewire-alsa`, or `bluetooth`. Even started by hand, `wpctl status`
   failed outright (`can't load dbus library: support/libspa-dbus`) because
   the dbus SPA plugin was never compiled.
3. Even the wrong/running daemon was muted at 6% volume, so nothing would
   have been audible regardless of (1) and (2).

Fixed:

- `/etc/portage/package.use/loupax-wm` — added
  `media-video/pipewire dbus sound-server pipewire-alsa bluetooth`. `dbus`
  fixes the SPA plugin load failure; `sound-server` builds the pipewire-pulse
  compat daemon; `pipewire-alsa` gives native ALSA apps a direct PipeWire
  route instead of only the pulse-compat path; `bluetooth` because there's a
  BT adapter on this machine and the cost of enabling it is basically free
  (`net-wireless/bluez` pulled in as a dependency). Not yet tested with an
  actual BT device.
- `emerge --oneshot media-video/pipewire` to rebuild with those flags. This
  also un-commented the `pipewire -c pipewire-pulse.conf` line in
  `/usr/bin/gentoo-pipewire-launcher` (the ebuild's own `src_install` gates
  that line on the `sound-server` flag).
- `media-sound/pulseaudio-daemon` ended up gone on its own — by the time we
  ran `emerge --unmerge` for it explicitly, portage reported it already
  couldn't find it to unmerge. Almost certainly auto-removed as part of the
  pipewire merge transaction resolving a blocker against it (pipewire's
  `sound-server` RDEPEND commonly blocks the standalone pulseaudio daemon
  once enabled) — not confirmed from a saved emerge log, but consistent with
  the timing and with `qlist -Iv` no longer showing it afterward.
- **Deliberately did not wire PipeWire into `startdwl`.** Explicit ask: audio
  shouldn't be coupled to whether dwl is running. Instead wrote an OpenRC
  *user service* — `~/.config/rc/init.d/pipewire-session` — that wraps
  Gentoo's own `/usr/bin/gentoo-pipewire-launcher` (ships with the pipewire
  ebuild, exists specifically for non-systemd users) in its own private
  `dbus-run-session`, same pattern `startdwl` already uses for dwl itself
  since this box has no elogind/systemd session-bus autolaunch. Enabled via
  `rc-update --user add pipewire-session default`, so it starts on login via
  `pam_openrc` regardless of what compositor (if any) runs afterward.
  `stop_post()` sweeps `pkill -x 'pipewire|wireplumber'` on stop, since
  `gentoo-pipewire-launcher` backgrounds the `pipewire` process before
  `exec`-ing into `wireplumber`, so `pipewire` isn't a child of the
  supervised pid and would otherwise survive a normal stop.
- Verified end to end: `wpctl status` shows the sink/source
  (`Ryzen HD Audio Controller Analog Stereo`), `pactl info` reports
  `PulseAudio (on PipeWire 1.6.7)` confirming pipewire-pulse owns the compat
  socket, and audio audibly works (tested via YouTube in a browser).

~~Left pending: `wpctl`/pipewire logs show RTKit realtime-priority
warnings~~ — `usermod -aG pipewire loupax` applied and confirmed active after
re-login. Bluetooth (USE flag + `bluez` installed back when the pipewire USE
flags were fixed) still untested — deferred until there's an actual BT
device around to pair.
