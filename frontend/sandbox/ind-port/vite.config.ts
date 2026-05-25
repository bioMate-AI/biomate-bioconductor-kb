import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

// Sandbox Vite config — runs the IND port standalone.
//   cd frontend/sandbox/ind-port
//   npx vite --port 7791
// or from the frontend dir:
//   npx vite --config sandbox/ind-port/vite.config.ts --port 7791
//
// Production at frontend/client/src/pages/ind-report.tsx is unaffected;
// the main vite.config.ts is untouched.
export default defineConfig({
  plugins: [react()],
  root: __dirname,
  resolve: { preserveSymlinks: false },
  // Cache to a sandbox-local dir so the parent frontend's .vite cache isn't
  // touched.
  cacheDir: path.resolve(__dirname, ".vite-cache"),
  server: {
    port: 7791,
    strictPort: false,
    // Polling-mode file watching — the host has hit the inotify watcher
    // limit from other dev servers. Polling is slower but reliable.
    watch: {
      usePolling: true,
      interval: 1000,
      ignored: ["**/node_modules/**", "**/.git/**", "**/dist/**"],
    },
    proxy: {
      "/api": {
        target: "http://localhost:8080",
        changeOrigin: true,
        secure: false,
      },
    },
  },
});
