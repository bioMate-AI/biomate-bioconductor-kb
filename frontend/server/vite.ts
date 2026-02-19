/**
 * Vite Development Server Setup
 *
 * Configures Vite middleware for development mode with HMR (Hot Module Replacement)
 * and serves static assets in production mode.
 */

import express, { type Express } from "express";
import type { ViteDevServer } from "vite";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/**
 * Setup Vite dev server middleware for development
 */
export async function setupVite(app: Express, server: any) {
  const vite = await import("vite");

  const viteDevServer = await vite.createServer({
    configFile: path.resolve(__dirname, "../vite.config.ts"),
    server: {
      middlewareMode: true,
      hmr: {
        server,
      },
    },
    appType: "custom",
  });

  app.use(viteDevServer.middlewares);

  // Serve index.html for all non-API routes (SPA fallback)
  app.use("*", async (req, res, next) => {
    const url = req.originalUrl;

    try {
      const clientTemplate = path.resolve(__dirname, "..", "client", "index.html");

      // Always reload the index.html file from disk in case it changes
      let template = await fs.promises.readFile(clientTemplate, "utf-8");
      const page = await viteDevServer.transformIndexHtml(url, template);
      res.status(200).set({ "Content-Type": "text/html" }).end(page);
    } catch (e) {
      viteDevServer.ssrFixStacktrace(e as Error);
      next(e);
    }
  });

  return viteDevServer;
}

/**
 * Serve static files in production mode
 */
export function serveStatic(app: Express) {
  const distPath = path.resolve(__dirname, "../client/dist");
  const indexPath = path.join(distPath, "index.html");

  // Serve static assets
  app.use(express.static(distPath));

  // Serve index.html for all non-API routes (SPA fallback)
  app.get("*", (req, res) => {
    if (!req.path.startsWith("/api")) {
      res.sendFile(indexPath);
    }
  });
}

/**
 * Logger utility
 */
export function log(...args: any[]) {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}]`, ...args);
}
