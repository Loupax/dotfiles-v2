static const Block blocks[] = {
	/* icon   command                                         interval  signal */
	{"",    "/usr/libexec/someblocks/sb-network",               2,        0},
	{"",  "/usr/libexec/someblocks/sb-notifications",            0,        4},
	{"",  "/usr/libexec/someblocks/sb-recorder",                 1,        0},
	{"",  "/usr/libexec/someblocks/sb-media",                    0,        3},
	{"󰕾 ",  "/usr/libexec/someblocks/sb-volume",                 0,        2},
	{"󰻠 ",  "/usr/libexec/someblocks/sb-cpu",                    2,        0},
	{"󰍛 ",  "/usr/libexec/someblocks/sb-memory",                 2,        0},
	{"",  "/usr/libexec/someblocks/sb-battery",                30,       0},
	{"",   "/usr/libexec/someblocks/sb-lang",                   0,        1},
	{"󰃭 ",  "date '+%I:%M %p - %a, %d %b %Y'",                              30,       0},
};

static char delim[64] = "  |  ";
static unsigned int delimLen = 5;
