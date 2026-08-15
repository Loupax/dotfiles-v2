# Copyright 2026 Kostas Loupasakis
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit toolchain-funcs

ESCM_REPO_URI="https://git.sr.ht/~leon_plickat/wlopm"

if [[ ${PV} == 9999 ]]; then
	inherit git-r3
	EGIT_REPO_URI="${ESCM_REPO_URI}"
fi

DESCRIPTION="CLI client for wlr-output-power-management-v1"
HOMEPAGE="https://git.sr.ht/~leon_plickat/wlopm"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS=""
IUSE=""

RDEPEND="dev-libs/wayland"
# wlopm.c includes <ffi.h> purely to check FFI_VERSION_NUMBER at compile time
# (prints a warning on newer libffi) -- no libffi functions are actually
# called or linked, so this is a build-time-only header dependency.
DEPEND="
	${RDEPEND}
	dev-libs/libffi
"
BDEPEND="
	dev-util/wayland-scanner
	virtual/pkgconfig
"

src_compile() {
	# Gentoo installs libffi's header outside the default include path
	# (/usr/lib64/libffi/include/ffi.h) -- needs pkg-config to be found.
	emake CC="$(tc-getCC)" CFLAGS="${CFLAGS} $(pkg-config --cflags libffi)" wlopm
}

src_install() {
	emake DESTDIR="${D}" PREFIX="${EPREFIX}/usr" install
}
