# Copyright 2026 Kostas Loupasakis
# Distributed under the terms of the GNU General Public License v2

EAPI=8

# waylock's own build.zig.zon pins these two Zig package-manager deps by
# content hash; see PACKAGING.md in the waylock source for why they must be
# vendored like this (Zig fetches them from the internet by default, which
# the Portage sandbox blocks).
declare -g -r -A ZBS_DEPENDENCIES=(
	[wayland-0.6.0-lQa1kqz8AQADQmdNJsNhLoNHcnEGEUjrOaPV-dtEnEmX.tar.gz]='https://codeberg.org/ifreund/zig-wayland/archive/v0.6.0.tar.gz'
	[xkbcommon-0.3.0-VDqIe3K9AQB2fG5ZeRcMC9i7kfrp5m2rWgLrmdNn9azr.tar.gz]='https://codeberg.org/ifreund/zig-xkbcommon/archive/v0.3.0.tar.gz'
)

ZIG_SLOT="0.15"
ZIG_NEEDS_LLVM=1
inherit zig

EGIT_REPO_URI="https://github.com/Loupax/waylock.git"
inherit git-r3

DESCRIPTION="waylock (Loupax fork) - Wayland screen locker, setuid+PAM"
HOMEPAGE="https://github.com/Loupax/waylock"

LICENSE="ISC"
SLOT="0"
KEYWORDS=""
IUSE="+man"

SRC_URI="${ZBS_DEPENDENCIES_SRC_URI}"

RDEPEND="
	sys-libs/pam
	dev-libs/wayland
	x11-libs/libxkbcommon
"
DEPEND="${RDEPEND}"
BDEPEND="
	>=dev-libs/wayland-protocols-1.32
	man? ( app-text/scdoc )
"

src_unpack() {
	git-r3_src_unpack
	zig_src_unpack
}

src_prepare() {
	zig_src_prepare

	# Zig 0.15.1's std.Build.Step.Run.captureStdOut() takes zero arguments;
	# this fork's build.zig still calls it with an empty options struct
	# (written against a different Zig std API version). One-line fix.
	sed -i 's/scdoc\.captureStdOut(\.{})/scdoc.captureStdOut()/' build.zig || die
}

src_configure() {
	local my_zbs_args=(
		-Doptimize=ReleaseSafe
		-Dllvm=true
		-Dstrip
		-Dpie
		-Dman-pages=$(usex man true false)
	)
	zig_src_configure
}

src_install() {
	zig_src_install

	# Required for PAM to read /etc/shadow when locking the session.
	fowners root:root /usr/bin/waylock
	fperms u+s /usr/bin/waylock
}

pkg_postinst() {
	ewarn "waylock is installed setuid root, and its PAM config"
	ewarn "(/etc/pam.d/waylock) intentionally bypasses pam_faillock."
	ewarn ""
	ewarn "Killing waylock forcefully (e.g. 'pkill waylock') will crash dwl:"
	ewarn "the compositor terminates the session on ext-session-lock-v1"
	ewarn "loss by design, to prevent the locker being bypassed. If locked"
	ewarn "out, switch to a TTY (Ctrl+Alt+F2), log in, then run"
	ewarn "'loginctl unlock-session <id>' or reboot."
}
