# Windowed resolution

ROSilicon can expose one extra windowed resolution sized to fit the primary
Mac display's usable area. In the launcher's **…** menu, check **Advertise
Usable-Screen Resolution**, then choose **Open Ragnarok Setup…** from the same
menu. Select the fitted resolution, keep the game in windowed mode, and save
it.

The calculation uses macOS's current usable screen frame, which already leaves
out the menu bar, notch and visible Dock. It also asks AppKit how much room the
Wine window's title bar occupies, so the whole outer window fits rather than
making only its client area as tall as the desktop. Dimensions are rounded
down to even values. On a 1470 by 956 display whose usable frame is 1470 by 923
and whose current title bar is 32 points tall, the result is 1470 by 890.

Unchecking **Advertise Usable-Screen Resolution** removes the extra mode from
Wine's list. It does not erase the resolution already saved by Ragnarok Setup;
open Setup and choose another mode if you want to change that selection.

This feature changes only the modes Wine advertises to Windows software in the
selected ROSilicon profile. It does not edit the game's `OptionInfo.lua`, does
not fabricate a physical Mac display mode, and does not support fullscreen
display switching for the fitted mode.
