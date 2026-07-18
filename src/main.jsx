import React from "react";
import { createRoot } from "react-dom/client";
import { SplashScreen } from "@capacitor/splash-screen";
import { loadRemote } from "./data/loadRemote";
import "./index.css";

// Fetch the freshest data (cache ▸ network ▸ bundled, ≤3s) BEFORE importing
// App, so App.jsx's module-level tables derive from it. The native splash
// (launchAutoHide:false) covers this brief wait; offline it resolves instantly
// against the bundled copy. See docs/going-live-fetch-at-runtime.md.
(async () => {
  await loadRemote();
  const { default: App } = await import("./App.jsx");
  createRoot(document.getElementById("root")).render(
    <React.StrictMode><App /></React.StrictMode>
  );
  // Hide the native splash once React has painted. The in-app <Splash> then
  // carries the brand for a beat and fades, so the handoff looks continuous.
  requestAnimationFrame(() => SplashScreen.hide().catch(() => {}));
})();
