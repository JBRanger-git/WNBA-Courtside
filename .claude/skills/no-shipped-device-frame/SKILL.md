---
name: no-shipped-device-frame
description: >-
  Ensures a web UI that is wrapped for a real device (Capacitor, Cordova, Tauri,
  a PWA, or React-Native-web) fills the actual screen and never ships the
  desktop-browser PREVIEW scaffolding — a hardcoded phone bezel, a fake status
  bar (e.g. "9:41 5G"), a notch mockup, or a fixed device-width container. Use
  this whenever building, reviewing, theming, or restyling the root layout / app
  shell of a mobile web app; whenever a root component hardcodes a device pixel
  width like 393 / 390 / 375 / 414 or draws a bezel/notch; when a device
  screenshot shows a "phone inside a phone", black bars, or the app floating in a
  margin; and as a pre-flight check before any Capacitor/Cordova release build.
  Trigger even if the user only says the app "looks wrong on device", "has a
  border around it", or asks to add dark mode / rework the shell — the shell is
  exactly where this bug hides.
---

# Don't ship the phone-preview frame

## The failure mode (why this skill exists)

Web UIs destined for a native wrapper are usually developed in a desktop
browser. To make them *look* like a phone during development, it's tempting to
wrap the whole app in a mock: a fixed-width column (e.g. `width: 393`), a dark
rounded **bezel**, a drop shadow, and a fake **status bar** ("9:41 · 5G").

That mock is a browser-preview affordance. It must never reach the real app —
because on an actual device the app **already fills the screen**. If the mock
ships, the user gets a **phone inside a phone**: a tiny cream (or dark) rounded
rectangle floating in the middle of their display, with a *fake* "9:41" clock
sitting under their *real* clock. It looks broken, and it's easy to miss because
in the browser (where you develop) it looks perfect.

This shipped once in a real Capacitor app. It rendered fine in every browser
test and only revealed itself as a screenshot from a physical phone. The lesson:
**the thing that makes it look like a phone in the browser is the exact thing
that breaks it on a phone.**

## How to detect it

Scan the **root/shell component** (the top-level `App`, the layout that wraps
every screen) for any of these. Each is a strong signal:

- A **fixed device width** on a container: `width: 393` / `390` / `375` / `414`
  / `428`, or `maxWidth` set to one of those. Real apps size to the viewport,
  not to one model of phone.
- A **fake status bar**: literal strings like `9:41`, `100%`, a battery/signal
  glyph, or `5G`/`LTE` rendered by the app itself. The OS already draws the real
  one.
- **Bezel / notch chrome**: a wrapping element with a large `borderRadius`
  (e.g. 40+), a dark frame colour behind the content (`#111`, `#000`), a big
  `boxShadow` used to fake device elevation, or an SVG/`div` "notch".
- Layout that **centres a fixed box**: `justifyContent: center` +
  `alignItems: flex-start` on a full-height parent whose only child is the
  fixed-width mock.

Fast grep over the shell / root files:

```
rg -n "9:41|375px|390px|393px|414px|428px|borderRadius: *(3[5-9]|[4-9][0-9])|notch|bezel|deviceframe|device-frame" src
```

Treat any hit **in the app shell** as guilty until proven a real feature. (A
`borderRadius` on a card is fine; one on the element that wraps the entire app is
not.)

## The fix

The app shell should **fill the real screen** and lean on the platform's own
status bar and safe areas — never simulate them.

1. **Fill the viewport.** The root fills `100%` height of a full-height
   `html, body, #root`, or uses `100dvh`. No fixed device width; width is `100%`.
2. **Delete the fake chrome.** Remove the bezel wrapper, the drop shadow, the
   simulated status bar, and any fixed-width centring. The screens themselves,
   not a mock, are the top-level content.
3. **Respect real safe areas** so content clears the notch and the gesture bar:
   ```css
   /* on body (or the shell), with viewport-fit=cover in the <meta> tag) */
   padding: env(safe-area-inset-top) env(safe-area-inset-right)
            env(safe-area-inset-bottom) env(safe-area-inset-left);
   ```
   and in `index.html`:
   ```html
   <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
   ```
4. **Theme the real surfaces.** If there's a dark mode, set `document.body`'s
   background and `color-scheme` so the safe-area strips match the app — don't
   paint a fake frame colour behind the content.

Keeping a phone preview for development is fine — but do it **outside** the app
(browser devtools device emulation, a Storybook frame, a `?preview` route that
never ships), not baked into the shell everyone downloads.

## Verify on a real surface, not a centred mock

The bug is invisible in a naïve browser view, so prove the fix the way the device
sees it:

- Render/screenshot at a **true device viewport** (e.g. Playwright
  `viewport: { width: 393, height: 852 }`) and confirm the app content reaches
  **all four edges** — no rounded corners, no dark frame, no floating box, no
  duplicate status bar.
- Best of all, screenshot on a **physical device or emulator** before release.
  The original bug only showed up there.

## Pre-ship checklist (Capacitor/Cordova/PWA)

- [ ] No fixed device width on the app shell (`width: 100%`, not `393`).
- [ ] No app-drawn status bar text (no "9:41", battery, signal, "5G").
- [ ] No bezel/notch/`borderRadius`/frame-colour wrapping the whole app.
- [ ] Root fills `100dvh`/`100%`; safe-area insets applied; `viewport-fit=cover`.
- [ ] Verified at a real device viewport (edge-to-edge) — ideally on hardware.
