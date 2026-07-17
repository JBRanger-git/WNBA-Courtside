import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  // Capacitor loads from file:// — relative base is required or assets 404 on device.
  base: "./",
  build: { outDir: "dist", assetsInlineLimit: 0 },
});
