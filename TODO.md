# TODO: package the symlink bootstrap as an ebuild

Goal: an ebuild in the `loupax-wm` overlay (alongside `dwl`, `somebar`, etc.)
that, on `emerge`, wires every file under `configs/` into its real location —
so provisioning a fresh machine (or re-provisioning this one) is `emerge
loupax-dotfiles` instead of replaying `SETUP-LOG.md` by hand.

Not started yet — this is the planning doc. Work through the open questions
together before writing any ebuild code.

## Current inventory — every symlink that exists today, made by hand

User-space (`$HOME`, owned by `loupax`):

| Live path | Points at |
|---|---|
| `~/.bashrc` | `configs/bash/bashrc` |
| `~/.config/tmux/tmux.conf` | `configs/tmux/tmux.conf` |
| `~/.config/tofi` (whole dir) | `configs/tofi` |
| `~/.config/vifm` (whole dir) | `configs/vifm` |
| `~/.config/dwl/wallpaper.png` (single file, not whole dir — see below) | `configs/dwl/wallpaper.png` |
| `~/.local/bin/startdwl` | `configs/dwl/startdwl` |
| `~/.local/bin/tofi_run_history` | `configs/scripts/tofi_run_history` |
| `~/.local/bin/recorder` | `configs/scripts/recorder` |
| `~/.local/bin/tmux-sessionizer` | `configs/sessionizer/tmux-sessionizer` |
| `~/.local/bin/vifm` | `configs/scripts/vifm` |
| `~/.local/share/wayland-sessions/dwl.desktop` | `configs/dwl/dwl.desktop` |

System-space (`/etc`, owned by `root`):

| Live path | Points at |
|---|---|
| `/etc/acpi/events/lid` | `configs/acpi/events/lid` |
| `/etc/acpi/lid.sh` | `configs/acpi/lid.sh` |
| `/etc/tlp.d/00-battery-tuning.conf` | `configs/tlp/00-battery-tuning.conf` |

Deliberate non-symlinks (need to stay this way, ebuild must not touch them):

- `~/.config/dwl/env` — machine-local, git-ignored, copied from
  `configs/dwl/env.example` once and then hand-edited. Symlinking the whole
  `~/.config/dwl` directory (like `tofi`/`vifm` do) was tried and reverted
  early in this repo's history for exactly this reason — see `SETUP-LOG.md`'s
  "First successful boot" section. The ebuild must replicate this split
  (symlink `wallpaper.png` alone, leave `env` as a real local file) rather
  than naively symlinking the parent directory.

Known gap, not yet migrated into `configs/` at all:

- `~/.config/foot/` (`foot.ini` + `themes/`) — still a plain untracked
  directory, per the buildout memory. Decide: pull it into `configs/foot/`
  as part of this work, or leave it out of the ebuild's scope for now and
  keep it a manual TODO.

## Open design questions — resolve before writing the ebuild

1. **Package shape**: one ebuild covering everything, or split
   system (`/etc`) vs. user (`$HOME`) into two packages? They have very
   different risk profiles — `/etc` writes are root-owned and small in
   number; `$HOME` writes require knowing *which* human user to target,
   which portage has no native concept of.
2. **Which user?** Portage runs `pkg_postinst()` as root with no built-in
   idea of "the human sitting at this seat." Options: hardcode `loupax`
   in the ebuild (simplest, matches this being a personal single-user
   overlay already), or read a variable (e.g. from `/etc/portage/make.conf`
   or a small env file) so the overlay isn't hardcoded to one name.
3. **Idempotency / don't clobber real content**: for each (source,
   destination) pair, the logic needs to be: already a correct symlink →
   skip silently; missing → create (mkdir -p the parent first); exists and
   is *not* the expected symlink (a real file/dir, or a symlink elsewhere)
   → **do not touch it**, `ewarn` and leave it for manual resolution. This
   is what protects things like `~/.config/dwl/env` even if it's
   accidentally included in the wrong list.
4. **Un-merge story**: `pkg_postinst` side effects aren't tracked by
   portage the way real merged files are — `emerge --unmerge` won't remove
   these symlinks automatically. Decide whether `pkg_postrm()` should
   remove exactly the symlinks this ebuild created (needs to record what
   it actually did, not just what it intended to do, so it never deletes
   something it didn't create) — or whether cleanup just stays manual and
   documented.
5. **`/etc` + `CONFIG_PROTECT`**: confirm `/etc/acpi/` and `/etc/tlp.d/`
   aren't under portage's `CONFIG_PROTECT` paths (they shouldn't be, since
   nothing else installs default configs there that would conflict) —
   double check with `emerge --info | grep CONFIG_PROTECT` before assuming.
6. **Versioning**: live `-9999` ebuild like `dwl`/`somebar` (re-runs
   `pkg_postinst` — and therefore re-syncs symlinks — on every manual
   re-merge, matching how the rest of `loupax-wm` already works), or a
   normal versioned ebuild bumped by hand when `configs/` changes
   meaningfully? Live ebuild seems like the natural fit given the rest of
   the overlay, but worth deciding explicitly rather than defaulting to it.
7. **Testing plan**: this machine already has every symlink in place by
   hand — first real test of the ebuild will be a no-op run against
   already-correct state. Want a second, deliberately "dirty" test case
   (e.g. temporarily `rm` one symlink, confirm the ebuild recreates just
   that one and leaves everything else alone) before trusting it on a
   genuinely fresh machine.

## Rough shape (draft, not final — refine together)

```bash
# pkg_postinst() sketch — one array of "source:dest:owner" triples,
# looped with the skip/create/warn logic from question 3 above.
LINKS_USER=(
    "configs/bash/bashrc:/home/${TARGET_USER}/.bashrc"
    "configs/tmux/tmux.conf:/home/${TARGET_USER}/.config/tmux/tmux.conf"
    "configs/tofi:/home/${TARGET_USER}/.config/tofi"
    "configs/vifm:/home/${TARGET_USER}/.config/vifm"
    "configs/dwl/wallpaper.png:/home/${TARGET_USER}/.config/dwl/wallpaper.png"
    # ... rest of the table above
)
LINKS_ETC=(
    "configs/acpi/events/lid:/etc/acpi/events/lid"
    "configs/acpi/lid.sh:/etc/acpi/lid.sh"
    "configs/tlp/00-battery-tuning.conf:/etc/tlp.d/00-battery-tuning.conf"
)
```

## Next session agenda

1. Walk through open questions 1–6 above, decide each one.
2. Decide on `configs/foot/` migration — in scope now or separate follow-up.
3. Write the ebuild in `overlays/gentoo/app-misc/loupax-dotfiles/` (or
   wherever we land on question 1).
4. Test against this machine's already-correct state (no-op check), then
   the "dirty" single-symlink-removed case.
5. If it all works, update `SETUP-LOG.md` to record the switch from
   manual symlinking to the ebuild.
