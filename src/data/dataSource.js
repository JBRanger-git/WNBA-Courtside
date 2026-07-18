// Single source of truth for the app's dataset. Defaults to the bundled
// snapshot (guaranteed offline fallback and what ships in the APK), and is
// swapped to a fresher copy by loadRemote() before App.jsx's module body runs.
// See docs/going-live-fetch-at-runtime.md.
import bundled from "./app-data.json";

let current = bundled;

export const setData = (d) => { current = d; };
export const getData = () => current;
