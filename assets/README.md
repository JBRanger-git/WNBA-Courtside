# App icon & native splash

The launch experience is two layers (see the splash notes in `CLAUDE.md`-adjacent
code):

1. **Native splash** — shown instantly on cold start, before the WebView loads.
   Configured in `capacitor.config.json` under `plugins.SplashScreen`
   (`backgroundColor` = `#F4F2EC`, `launchAutoHide: false`). It's hidden
   programmatically in `src/main.jsx` once the web app paints its first frame.
2. **In-app splash** — the `Splash` component in `src/App.jsx`, same cream
   background and Courtside mark, which fades into the app. The native → web
   handoff is seamless because both look identical.

This already gives a working splash with no white flash. The only thing that
needs generating is the **native splash image and the app icon**, which requires
the Android project — do it on your machine after `npx cap add android`.

## Generating the images

`assets/courtside-icon.svg` is the brand source (font-free so it rasterises
cleanly). Use the official generator:

```bash
npm i -D @capacitor/assets
# a 1024×1024 source is expected; convert the SVG once (any tool), e.g.:
#   rsvg-convert -w 1024 -h 1024 assets/courtside-icon.svg > assets/icon.png
#   cp assets/icon.png assets/splash.png        # simple centred mark works for both
npx @capacitor/assets generate --android \
  --iconBackgroundColor '#F4F2EC' \
  --splashBackgroundColor '#F4F2EC'
npx cap sync android
```

That writes the density-specific icon and splash assets into `android/`.
`android/` is gitignored and disposable, so this is a per-machine step.

## Notes
- Keep the background `#F4F2EC` everywhere so the native → web splash handoff
  stays invisible.
- The mark is deliberately typographic/geometric and uses **our own** colours —
  no third-party imagery (see `CLAUDE.md` → Imagery).
- Want the icon to be the full wordmark instead of the "C" mark? Swap the source
  SVG; a monogram reads better at 48 px, which is why the default is the mark.
