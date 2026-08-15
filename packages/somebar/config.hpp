// somebar - dwl bar
// See LICENSE file for copyright and license details.

#pragma once
#include "common.hpp"

constexpr bool topbar = true;

constexpr int paddingX = 10;
constexpr int paddingY = 3;

// See https://docs.gtk.org/Pango/type_func.FontDescription.from_string.html
constexpr const char* font = "0xProto Nerd Font Mono 12";

constexpr ColorScheme colorInactive = {Color(0xB0, 0xAC, 0xBB), Color(0x1B, 0x2E, 0x4D, 0xCC)};
constexpr ColorScheme colorActive = {Color(0xee, 0xee, 0xee), Color(0x98, 0x55, 0x6B)};

constexpr const char* termcmd[] = {"foot", nullptr};


constexpr Button buttons[] = {
	{ ClkTagBar,       BTN_LEFT,   view,       {0} },
	{ ClkTagBar,       BTN_RIGHT,  toggleview, {0} },
	{ ClkStatusText,   BTN_RIGHT,  spawn,      {.v = termcmd} },
};
