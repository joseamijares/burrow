# The window Burrow-<version>.dmg opens in, for dmgbuild (native/scripts/package-dmg.sh).
# Same layout as Daybook's dmg/settings.py: the app on the left, an arrow to
# Applications on the right, on Burrow's paper (dmg/background.tiff, 1x and 2x,
# drawn by dmg/make-background.swift from the Paper file's tokens).
import os.path

application = defines["app"]  # noqa: F821 (dmgbuild passes -D app=…)
appname = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
hide_extensions = [appname]

background = defines["background"]  # noqa: F821
# 420 for the background, plus the 28pt title bar Finder takes from it.
window_rect = ((200, 140), (660, 448))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False

icon_size = 112
text_size = 13
label_pos = "bottom"
icon_locations = {appname: (170, 196), "Applications": (490, 196)}
