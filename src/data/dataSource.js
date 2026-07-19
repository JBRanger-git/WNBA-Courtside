// Single source of truth for the app's dataset. Defaults to the bundled
// snapshot (guaranteed offline fallback and what ships in the APK), and is
// swapped to a fresher copy by the loader. Components re-derive and re-render
// via subscribe() when the data changes mid-session (Phase 2 live refresh).
// See docs/going-live-fetch-at-runtime.md.
import bundled from "./app-data.json";

let current = bundled;
const listeners = new Set();

export const getData = () => current;

export const setData = (d) => {
  if (!d || d === current) return;
  current = d;
  listeners.forEach((fn) => { try { fn(); } catch {} });
};

// Returns an unsubscribe function. Called with no args when the data changes.
export const subscribe = (fn) => {
  listeners.add(fn);
  return () => listeners.delete(fn);
};
