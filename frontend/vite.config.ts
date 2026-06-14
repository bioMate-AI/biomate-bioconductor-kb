import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  resolve: {
    // Force a SINGLE React instance across the bundle. Without this, any
    // transitive dependency that ships its own React copy (jsx-runtime,
    // hooks) gives the app TWO Reacts at runtime — when @tanstack/react-query
    // (or any context provider) calls useEffect, it reaches a different
    // React than the component tree, the dispatcher is null, and the app
    // crashes at render with
    //   TypeError: Cannot read properties of null (reading 'useEffect')
    // at QueryClientProvider.
    //
    // Surfaced 2026-06-14 when concurrent agent work on bioc/v2-qc-audit-panel
    // added a new dep that pulled its own React copy. dedupe is the standard
    // Vite fix per @tanstack/react-query troubleshooting docs.
    dedupe: ["react", "react-dom"],
    alias: {
      "@": path.resolve(__dirname, "client", "src"),
      "@shared": path.resolve(__dirname, "shared"),
      "@assets": path.resolve(__dirname, "attached_assets"),
    },
  },
  root: path.resolve(__dirname, "client"),
  build: {
    outDir: path.resolve(__dirname, "dist/public"),
    emptyOutDir: true,
  },
  server: {
    proxy: {
      "/api": {
        target: "http://localhost:8080",
        changeOrigin: true,
        secure: false,
      },
    },
  },
});
