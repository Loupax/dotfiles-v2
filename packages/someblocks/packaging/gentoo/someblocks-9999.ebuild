# Copyright 2026 Kostas Loupasakis
# Distributed under the terms of the GNU General Public License v2

EAPI=8

inherit toolchain-funcs

EGIT_REPO_URI="https://github.com/Loupax/someblocks.git"
inherit git-r3

DESCRIPTION="someblocks (Loupax fork) - status block runner for somebar, personal config"
HOMEPAGE="https://github.com/Loupax/someblocks"

LICENSE="MIT"
SLOT="0"
KEYWORDS=""
IUSE=""

src_prepare() {
	cp "${FILESDIR}"/blocks.h blocks.h || die

	default
}

src_compile() {
	emake CC="$(tc-getCC)" output
}

src_install() {
	dobin someblocks
	doman someblocks.1

	# blocks.h points at /usr/libexec/someblocks/sb-* — install the status
	# scripts there so the paths compiled into the binary resolve.
	exeinto /usr/libexec/someblocks
	doexe scripts/sb-*
}
