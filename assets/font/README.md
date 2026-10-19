# Bundled fonts

Three pixel faces. Their terms differ — read each before reusing it.

## FlipperBold — `flipper-bold.ttf`

The face on every `ProgressButton`, including the firmware install button.
Registered as family `FlipperBold` at weight 500. An unresolvable `fontFamily`
is not an error: Flutter draws the whole label in the system face instead, at
the pixel size this button asks for, so the label clips.

## Born2bSportyV2 — `born2b-sporty-v2.ttf`

The smaller face on the about page. Public domain, JapanYoshi.

## GravityBold8 — `gravity-bold-8.ttf`

The large display face on the about page, from the [Gravity Pixel Font
Pack](https://jotson.itch.io/gravity-pixel-font) by jotson, the fonts used in
Gravity Ace.

**Its terms are only what that page says.** In full:
"two pixel-perfect TTF fonts — as seen in the game Gravity Ace — that you can
use in your commercial or non-commercial projects and games", plus "You can
import the included .txt files back into BitFontMaker2 to edit the fonts and
re-export new versions." That covers use in a project and editing. It says
nothing about redistributing the face on its own, there is no licence file in
the pack, and the `.ttf` carries no licence record — its copyright field is just
`JohnWatson`. Treat it as bundled-with-the-app only.

It maps exactly 96 codepoints: `U+0020`–`U+007E` plus `U+00A0`. **No Cyrillic at
all.** Every string set in it is a hardcoded English word (`Unleashed`,
`firmware`), so nothing localised reaches it; anything localised that ever does
will fall back wholesale. The source page also notes it is pixel-exact only at
sizes that are multiples of 8, and `about/widgets/pixel_button.dart` renders it
at 28.
