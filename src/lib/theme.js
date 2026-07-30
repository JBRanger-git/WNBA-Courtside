// Ported from wnba-chalk-court-theme.json — same tokens as the Power BI report.
// Two intentional adaptations for a real Android app (not a 1:1 port):
//   1. DIN has no web license. The desktop mockups already fall back to
//      Oswald, so we keep that fallback here for consistency.
//   2. Segoe UI does not exist on Android. Forcing it renders as generic
//      sans-serif with no benefit, so body text uses the system stack
//      (Roboto on most Android devices) instead.

export const color = {
  page: "#F4F2EC",
  card: "#ECEAE2",
  visual: "#FFFFFF",
  stripe: "#F7F6F1",
  border: "#DEDBD2",
  text: "#15151C",
  textSecondary: "#5B6472",
  textMuted: "#8A8F98",
  accent: "#FE5000", // tableAccent — reserved for accents/highlights, never a data series
  good: "#1E8F5E",
  bad: "#C23934",
  dataColors: [
    "#3B6FC4", "#5B6472", "#1E8F5E", "#C4832E",
    "#7C5FB5", "#3E9E8C", "#B85D82", "#C23934",
  ],
};

export const font = {
  display: "'Oswald', sans-serif",
  body: "'Roboto', 'Segoe UI', system-ui, sans-serif",
};

// Oswald is bundled locally (src/App.jsx's @font-face, from
// src/assets/fonts/oswald-var.woff2) — the app has no INTERNET permission, so
// a live Google Fonts URL here would fail silently on device.
