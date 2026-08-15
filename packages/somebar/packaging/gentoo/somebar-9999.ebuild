# Copyright 2026 Kostas Loupasakis
# Distributed under the terms of the GNU General Public License v2

EAPI=8

EGIT_REPO_URI="https://github.com/Loupax/somebar.git"
inherit git-r3 meson

DESCRIPTION="somebar (Loupax fork) - status bar for dwl, personal config"
HOMEPAGE="https://github.com/Loupax/somebar"

LICENSE="ISC"
SLOT="0"
KEYWORDS=""
IUSE=""

RDEPEND="
	dev-libs/wayland
	x11-libs/cairo
	x11-libs/pango
"
DEPEND="${RDEPEND}"
BDEPEND="
	>=dev-libs/wayland-protocols-1.32
	dev-util/wayland-scanner
	virtual/pkgconfig
"

src_prepare() {
	cp "${FILESDIR}"/config.hpp src/config.hpp || die

	# Upstream's zwlr_layer_surface_v1_listener never registers a handler for
	# the "closed" event (opcode 1) -- compositors send this when an output
	# is removed/re-added (e.g. on a VT switch away and back), and with no
	# listener installed libwayland-client fatally aborts the process:
	# "listener function for opcode 1 of zwlr_layer_surface_v1 is NULL".
	# Bar::hide() already exists and is the obvious handler; just never wired
	# up. (This exact fix already exists in the v1 monorepo's local copy of
	# somebar, it was just never pushed to the Loupax/somebar fork itself --
	# ought to be pushed upstream at some point instead of patched here.)
	python3 - <<'EOF' || die
import pathlib
p = pathlib.Path("src/bar.cpp")
old = """\t[](void* owner, zwlr_layer_surface_v1*, uint32_t serial, uint32_t width, uint32_t height)
\t{
\t\tstatic_cast<Bar*>(owner)->layerSurfaceConfigure(serial, width, height);
\t}
};"""
new = """\t[](void* owner, zwlr_layer_surface_v1*, uint32_t serial, uint32_t width, uint32_t height)
\t{
\t\tstatic_cast<Bar*>(owner)->layerSurfaceConfigure(serial, width, height);
\t},
\t[](void* owner, zwlr_layer_surface_v1*)
\t{
\t\tstatic_cast<Bar*>(owner)->hide();
\t}
};"""
text = p.read_text()
assert old in text, "expected _layerSurfaceListener block not found in bar.cpp"
p.write_text(text.replace(old, new, 1))
EOF

	default
}
