import React from "react";
import { createRoot } from "react-dom/client";
import { SplashScreen } from "@capacitor/splash-screen";
import { applyCache, refreshFromNetwork } from "./data/loadRemote";
import "./index.css";

// Phase 2: no network wait. Seed the freshest cached snapshot synchronously
// (applyCache) before App's tables compute, render immediately, then refresh
// from the network in the background — newer data swaps in live via the
// dataSource subscribers. Offline, the bundled copy renders instantly.
// See docs/going-live-fetch-at-runtime.md.
applyCache();

import("./App.jsx").then(({ default: App }) => {
  createRoot(document.getElementById("root")).render(
    <React.StrictMode><App /></React.StrictMode>
  );
  // Hide the native splash once React has painted; the in-app <Splash> carries
  // the brand for a beat and fades, so the handoff looks continuous.
  requestAnimationFrame(() => SplashScreen.hide().catch(() => {}));
  refreshFromNetwork();
});
