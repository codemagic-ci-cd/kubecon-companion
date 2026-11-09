# Codemagic brand (from the Codemagic Design System)

Assets in this repo: `assets/fonts/Metropolis-{Regular,SemiBold,Bold}.otf` (weights 400/600/700), `assets/brand/logo-blue.svg` (for light surfaces), `assets/brand/logo-white.svg` (for dark surfaces). Use `flutter_svg` to render logos.

## Color (use exactly, never tint or re-mix)
Brand palette (same in both themes):
- No Bug Blue `#0031EA`, Never Blue `#0051FF`, Continuous Blue `#008BF7`, Dash Aqua `#00CEFF`
- SWW Yellow `#FF9100`, Native Orange `#FF4D13`, Red `#EC0C43`, Pink Magic `#FE19FF`

Dark theme (default for this app):
- Page `#01091A`; card = flat gradient 160deg `#182238` -> `#101A2C`; card border (outer container only) `rgba(255,255,255,.10)`
- Heading text `#FFFFFF`, body text `#D2DBEE`
- Secondary/subtle button `#232A38` (hover `#2E3646`)
- Link hover on dark: `#FF9100`

Light theme:
- Page `#FFFFFF` (pure white, never off-white), card `#F2F5FA`, border `rgba(17,40,91,.08)`
- Heading `#11285B`, body `#3A4865`; subtle button `#F4F6FB` with `#11285B` text (hover `#E1E9FB`)

Buttons: primary solid `#0957FF` (pressed/hover `#0031EA`), white label. Emphasis gradients: blue `#0031EA -> #008BF7`, magenta `#FF9100 -> #FE19FF`.
Accent multi-hue gradient (`#0031EA, #008BF7, #00CEFF, #FE19FF, #FF4D13`) ONLY for heavily blurred background glows bleeding off an edge, never across text.

## Type
- Font family `Metropolis` for everything; mono = system monospace.
- Letter spacing -0.2 on every style; heading line height 1.26, body 1.5.
- Mobile scale: h1 28, h2 26, h3 22, h4 20, h5 18 (card titles, bold), h6 16; paragraph-lg 16, md 14, sm 14, xsm 12; action (buttons/labels) semibold 14.
- Weights: bold 700 headings, semibold 600 actions/nav, regular 400 body.
- Sentence case everywhere. NO uppercase eyebrows/kicker labels, no all-caps, no positive letter spacing. Body copy lower contrast than headings.

## Shape and spacing
- Radius: sm 8, md 12, cards 20, buttons 12, pill 999.
- Buttons 44px tall, min width 200 when standalone (can be full width in mobile sheets), equal side padding, no outline/ghost buttons; secondary = subtle neutral fill.
- Cards: flat fill, 20 radius, no shadow/glow, no inner card borders, no colored left-border accents. Padding 16-24 on mobile.
- Spacing scale 4, 8, 12, 16, 24, 32, 48, 64.

## Icons
Line (stroke) icons in Never Blue `#0051FF` on light, or white/`#D2DBEE` on dark.

## Map colors (derived, stay in palette)
Rooms: card fill; selected/target room: `#0051FF` with white label; route/level-change markers: `#FF9100`; landmarks: `#00CEFF`; food: `#FF4D13`.
