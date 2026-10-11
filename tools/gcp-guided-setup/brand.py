#!/usr/bin/env python3
"""The Abstract terminal header for the Google Cloud guided-setup tools - the same branding as the Abstract
Search & Export kit: the official lockup, the spaced gradient title and a status line.

usage: brand.py header TITLE SUBTITLE [STATUS ...]
  STATUS is "ok|text", "warn|text", "bad|text" or "info|text" - one coloured line each.

Truecolor terminals get the brand colours; 256- and 16-colour terminals get the nearest ones; NO_COLOR,
TERM=dumb, ABX_PLAIN=1 or output that is not a terminal get plain text (scripts and tests read that).
The lockup needs a window at least 64 columns wide, otherwise the word mark is shown.
"""
import os
import re
import shutil
import sys

# The official Abstract lockup and mark, rendered from the brand SVGs by gen_brand.py in the Abstract
# Search & Export kit (kits/gen_brand.py) and copied here unchanged. Never hand-edit or redraw them:
# regenerate there and copy both lists again.
LOCKUP = ['\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;252;29;105m▄\x1b[38;2;255;32;109m\x1b[48;2;255;28;116m▀\x1b[38;2;252;25;109m\x1b[48;2;243;18;99m▀\x1b[38;2;247;17;102m\x1b[48;2;255;13;107m▀\x1b[0m\x1b[38;2;236;5;95m▄\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m \x1b[0m\x1b[0m', '\x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;196;0;77m▄\x1b[38;2;255;30;112m\x1b[48;2;208;0;80m▀\x1b[0m\x1b[38;2;248;19;100m▀\x1b[0m\x1b[38;2;247;12;101m▀\x1b[38;2;244;5;99m\x1b[48;2;242;1;97m▀\x1b[38;2;231;0;93m\x1b[48;2;231;0;93m▀\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;255;255m▄\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[0m', '\x1b[0m \x1b[0m \x1b[38;2;191;0;75m\x1b[48;2;199;0;77m▀\x1b[38;2;221;0;87m\x1b[48;2;204;0;80m▀\x1b[0m\x1b[38;2;198;0;78m▀\x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;228;0;91m▀\x1b[38;2;255;35;107m\x1b[48;2;255;36;116m▀\x1b[0m\x1b[38;2;255;32;106m▄\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m \x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m\x1b[38;2;255;255;255m▄\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m', '\x1b[0m \x1b[38;2;193;0;76m\x1b[48;2;197;0;77m▀\x1b[38;2;216;0;85m\x1b[48;2;203;0;80m▀\x1b[0m\x1b[38;2;193;0;75m▀\x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;32;110m▄\x1b[0m\x1b[38;2;255;34;111m▄\x1b[38;2;255;34;109m\x1b[48;2;255;36;115m▀\x1b[38;2;255;33;108m\x1b[48;2;255;34;110m▀\x1b[38;2;255;35;114m\x1b[48;2;255;36;113m▀\x1b[0m\x1b[38;2;255;35;107m▄\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m \x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;255;255m▄\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m\x1b[0m', '\x1b[0m \x1b[0m\x1b[38;2;222;0;87m▀\x1b[0m\x1b[38;2;186;0;71m▀\x1b[0m\x1b[38;2;255;34;109m▄\x1b[0m\x1b[38;2;255;36;116m▄\x1b[38;2;253;34;109m\x1b[48;2;255;36;117m▀\x1b[38;2;255;37;120m\x1b[48;2;255;34;109m▀\x1b[0m\x1b[38;2;255;33;109m▀\x1b[0m\x1b[38;2;255;33;108m▀\x1b[0m \x1b[0m\x1b[38;2;230;0;92m▄\x1b[38;2;248;13;102m\x1b[48;2;255;0;104m▀\x1b[0m\x1b[38;2;231;0;92m▄\x1b[0m \x1b[0m \x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m \x1b[0m\x1b[38;2;255;255;255m▀\x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m \x1b[38;2;255;255;255m\x1b[48;2;255;255;255m▀\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m\x1b[38;2;255;255;255m▄\x1b[0m', '\x1b[0m\x1b[38;2;255;33;107m▀\x1b[38;2;255;36;111m\x1b[48;2;253;33;108m▀\x1b[38;2;255;34;109m\x1b[48;2;255;33;110m▀\x1b[38;2;255;36;118m\x1b[48;2;255;33;110m▀\x1b[0m\x1b[38;2;255;33;109m▀\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[38;2;237;0;94m\x1b[48;2;229;0;92m▀\x1b[0m\x1b[38;2;232;0;93m▀\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[0m']

MARK = ['\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;31;111m▄\x1b[38;2;255;30;109m\x1b[48;2;255;24;107m▀\x1b[38;2;252;21;105m\x1b[48;2;247;16;102m▀\x1b[0m\x1b[38;2;239;8;97m▄\x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[0m', '\x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;199;0;78m▄\x1b[38;2;255;28;113m\x1b[48;2;199;0;76m▀\x1b[0m\x1b[38;2;243;15;99m▀\x1b[38;2;248;9;100m\x1b[48;2;239;3;96m▀\x1b[38;2;248;2;100m\x1b[48;2;255;0;103m▀\x1b[0m\x1b[38;2;236;6;96m▄\x1b[0m \x1b[0m \x1b[0m\x1b[0m', '\x1b[0m \x1b[0m \x1b[38;2;191;0;75m\x1b[48;2;208;0;81m▀\x1b[38;2;229;0;90m\x1b[48;2;197;0;77m▀\x1b[0m\x1b[38;2;196;0;77m▀\x1b[0m \x1b[0m \x1b[0m\x1b[38;2;229;0;90m▀\x1b[38;2;247;23;103m\x1b[48;2;255;32;107m▀\x1b[38;2;255;35;106m\x1b[48;2;255;34;109m▀\x1b[0m \x1b[0m\x1b[0m', '\x1b[0m \x1b[38;2;191;0;74m\x1b[48;2;201;0;79m▀\x1b[38;2;218;0;85m\x1b[48;2;196;0;77m▀\x1b[0m\x1b[38;2;192;0;76m▀\x1b[0m \x1b[0m \x1b[0m\x1b[38;2;255;33;109m▄\x1b[38;2;255;33;108m\x1b[48;2;255;36;117m▀\x1b[38;2;255;34;110m\x1b[48;2;255;35;112m▀\x1b[38;2;255;35;115m\x1b[48;2;255;35;109m▀\x1b[38;2;255;32;107m\x1b[48;2;255;35;108m▀\x1b[0m\x1b[0m', '\x1b[0m \x1b[0m\x1b[38;2;225;0;88m▀\x1b[0m\x1b[38;2;184;0;70m▀\x1b[0m\x1b[38;2;255;33;109m▄\x1b[38;2;253;33;108m\x1b[48;2;255;37;120m▀\x1b[38;2;255;34;110m\x1b[48;2;255;33;109m▀\x1b[38;2;255;37;119m\x1b[48;2;255;34;109m▀\x1b[0m\x1b[38;2;255;32;108m▀\x1b[0m \x1b[0m \x1b[38;2;252;11;104m\x1b[48;2;244;0;98m▀\x1b[0m\x1b[38;2;233;0;92m▄\x1b[0m', '\x1b[0m\x1b[38;2;255;33;107m▀\x1b[38;2;255;36;112m\x1b[48;2;253;33;109m▀\x1b[38;2;255;35;112m\x1b[48;2;255;34;109m▀\x1b[38;2;255;36;117m\x1b[48;2;255;33;109m▀\x1b[0m\x1b[38;2;255;34;109m▀\x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m \x1b[0m\x1b[38;2;229;0;91m▀\x1b[38;2;245;0;98m\x1b[48;2;230;0;93m▀\x1b[0m']


PINK, DEEP = (255, 33, 107), (194, 0, 76)
TEAL, AMBER, GREY, DIMC = (1, 230, 157), (245, 198, 30), (139, 136, 150), (94, 91, 105)


def _tty():
    try:
        return sys.stdout.isatty()
    except Exception:
        return False


PLAIN = (not _tty() or os.environ.get("NO_COLOR") or os.environ.get("TERM", "").lower() == "dumb"
         or os.environ.get("ABX_PLAIN", "") not in ("", "0"))


def _level():
    if PLAIN:
        return 0
    if os.environ.get("COLORTERM", "").lower() in ("truecolor", "24bit") or \
            os.environ.get("TERM_PROGRAM", "") in ("iTerm.app", "vscode", "WezTerm", "ghostty", "Hyper"):
        return 24
    return 256 if "256" in os.environ.get("TERM", "") else 16


LEVEL = _level()
_RGB = re.compile(r"\x1b\[(38|48);2;(\d+);(\d+);(\d+)m")
_B16 = [(0, 0, 0), (205, 0, 0), (0, 205, 0), (205, 205, 0), (0, 0, 238), (205, 0, 205), (0, 205, 205), (229, 229, 229),
        (127, 127, 127), (255, 0, 0), (0, 255, 0), (255, 255, 0), (92, 92, 255), (255, 0, 255), (0, 255, 255),
        (255, 255, 255)]


def _x256(r, g, b):
    def cube(v):
        return 0 if v < 48 else 1 if v < 115 else (v - 35) // 40
    lv = [0, 95, 135, 175, 215, 255]
    grey = max(0, min(23, round(((r + g + b) / 3 - 8) / 10)))
    gv = 8 + 10 * grey
    dc = (lv[cube(r)] - r) ** 2 + (lv[cube(g)] - g) ** 2 + (lv[cube(b)] - b) ** 2
    dg = (gv - r) ** 2 + (gv - g) ** 2 + (gv - b) ** 2
    return 16 + 36 * cube(r) + 6 * cube(g) + cube(b) if dc <= dg else 232 + grey


def _n16(r, g, b):
    # Keep the brand legible: pinks become red, light pixels bright white, dark ones black.
    if r > 150 and g < 120 and b < 170:
        return 9 if r >= 235 else 1
    if r > 170 and g > 170 and b > 170:
        return 15
    if max(r, g, b) < 60:
        return 0
    return min(range(16), key=lambda k: sum((_B16[k][i] - (r, g, b)[i]) ** 2 for i in range(3)))


def _code(rgb, layer="38"):
    if LEVEL == 24:
        return "%s;2;%d;%d;%d" % ((layer,) + tuple(rgb))
    if LEVEL == 256:
        return "%s;5;%d" % (layer, _x256(*rgb))
    i = _n16(*rgb)
    return str((30 if layer == "38" else 40) + (i % 8) + (60 if i >= 8 else 0))


def fg(rgb, s):
    return f"\033[{_code(rgb)}m{s}\033[0m" if LEVEL else s


def gradient(text):
    if not LEVEL:
        return text
    n = max(1, len(text) - 1)
    mix = lambda f: tuple(round(PINK[k] + (DEEP[k] - PINK[k]) * f) for k in range(3))  # noqa: E731
    return "".join(f"\033[1;{_code(mix(i / n))}m{ch}" for i, ch in enumerate(text)) + "\033[0m"


def _art(line):
    if LEVEL == 24:
        return line
    return _RGB.sub(lambda m: f"\033[{_code((int(m.group(2)), int(m.group(3)), int(m.group(4))), m.group(1))}m", line)


def cols():
    return shutil.get_terminal_size((80, 24)).columns


DOTS = {"ok": TEAL, "warn": AMBER, "bad": PINK, "info": GREY}


def header(title, subtitle, statuses):
    if PLAIN:
        print(f"\nAbstract Security - {title} {subtitle}".rstrip())
        for kind, text in statuses:
            print(f"  * {text}")
        print("-" * 20)
        return
    print()
    for line in (LOCKUP if cols() >= 64 else ["", fg(PINK, "\033[1mA\033[0m") + " \033[1mabstract\033[0m", ""]):
        print("  " + _art(line))
    print()
    spaced = "   ".join(" ".join(w) for w in title.upper().split()) if cols() >= len(title) * 2 + 12 else title.upper()
    print("  " + gradient(spaced) + "   " + fg(GREY, subtitle))
    for kind, text in statuses:
        print("  " + fg(DOTS.get(kind, GREY), "●") + " " + text)
    print(fg(DIMC, "━" * max(20, cols() - 1)))


if __name__ == "__main__":
    if len(sys.argv) < 4 or sys.argv[1] != "header":
        sys.exit(__doc__)
    header(sys.argv[2], sys.argv[3], [s.split("|", 1) if "|" in s else ("info", s) for s in sys.argv[4:]])
