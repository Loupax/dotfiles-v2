# Copyright 2026 Kostas Loupasakis
# Distributed under the terms of the GNU General Public License v2

EAPI=8

EGIT_REPO_URI="https://github.com/philj56/tofi.git"
inherit git-r3 meson

DESCRIPTION="Tiny dynamic menu for Wayland, dmenu/rofi-compatible"
HOMEPAGE="https://github.com/philj56/tofi"

LICENSE="MIT"
SLOT="0"
KEYWORDS=""
IUSE="+man"

RDEPEND="
	dev-libs/glib
	dev-libs/wayland
	media-libs/freetype
	media-libs/harfbuzz
	x11-libs/cairo
	x11-libs/libxkbcommon
	x11-libs/pango
"
DEPEND="${RDEPEND}"
BDEPEND="
	>=dev-libs/wayland-protocols-1.32
	dev-util/wayland-scanner
	virtual/pkgconfig
	man? ( app-text/scdoc )
"

src_configure() {
	local emesonargs=(
		-Dman-pages=$(usex man enabled disabled)
	)
	meson_src_configure
}
