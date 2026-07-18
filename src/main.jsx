import React from "react";
import { createRoot } from "react-dom/client";
import { SplashScreen } from "@capacitor/splash-screen";
import App from "./App.jsx";
import "./index.css";

createRoot(document.getElementById("root")).render(
  <React.StrictMode><App /></React.StrictMode>
);

// Hide the native splash once the web app has painted its first frame. On the
// web this is a harmless no-op. The in-app <Splash> (App.jsx) then carries the
// brand for a beat and fades, so the native → web handoff looks like one
// continuous splash (same cream background + Courtside mark).
requestAnimationFrame(() => SplashScreen.hide().catch(() => {}));
