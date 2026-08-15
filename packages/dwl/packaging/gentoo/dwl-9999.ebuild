# Copyright 2026 Kostas Loupasakis
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit toolchain-funcs

EGIT_REPO_URI="https://github.com/Loupax/dwl.git"
inherit git-r3

DESCRIPTION="dwl (Loupax fork) - dwm for Wayland, personal config"
HOMEPAGE="https://github.com/Loupax/dwl"

LICENSE="CC0-1.0 GPL-3+ MIT"
SLOT="0"
KEYWORDS=""
IUSE="+X"

COMMON_DEPEND="
	>=gui-libs/wlroots-0.19:0.19=[libinput,session,X?]
	dev-libs/libinput:=
	dev-libs/wayland
	x11-libs/libxkbcommon
	X? (
		x11-libs/libxcb:=
		x11-libs/xcb-util-wm
	)
"
RDEPEND="
	${COMMON_DEPEND}
	X? ( x11-base/xwayland )
"
# uses <linux/input-event-codes.h>
DEPEND="
	${COMMON_DEPEND}
	sys-kernel/linux-headers
"
BDEPEND="
	>=dev-libs/wayland-protocols-1.32
	>=dev-util/wayland-scanner-1.23
	virtual/pkgconfig
"

src_prepare() {
	cp "${FILESDIR}"/config.h config.h || die

	default
}

src_compile() {
	local pkgconfig="$(tc-getPKG_CONFIG)"

	# The fork's config.mk hardcodes a WLROOTS_DIR pointing at a sibling
	# ../wlroots checkout (the monorepo layout it was written for); override
	# WLR_INCS/WLR_LIBS here so it links the system gui-libs/wlroots instead.
	emake \
		CC="$(tc-getCC)" \
		PKG_CONFIG="${pkgconfig}" \
		WLR_INCS="$(${pkgconfig} --cflags wlroots-0.19)" \
		WLR_LIBS="$(${pkgconfig} --libs wlroots-0.19)" \
		XWAYLAND="$(usev X -DXWAYLAND)" \
		XLIBS="$(usev X 'xcb xcb-icccm')" \
		dwl
}

src_install() {
	emake DESTDIR="${D}" PREFIX="${EPREFIX}/usr" install
	dodoc CHANGELOG.md README.md

	# The fork's own `startdwl` is installed as `ln -sf $(CURDIR)/startdwl ...`
	# by its Makefile -- a symlink into this ephemeral build directory, which
	# is dangling the moment the merge finishes. It's also written assuming
	# it lives inside the v1 monorepo (relative paths to wallpaper.jpg,
	# autostart.sh, etc.), which doesn't apply to a packaged install anyway.
	# v2 provides its own session launcher separately (see configs/); don't
	# ship this broken one.
	rm -f "${ED}"/usr/bin/startdwl
}
