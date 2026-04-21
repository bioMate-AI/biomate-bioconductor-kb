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
  // Serve reference design prototypes as static files (before Vite catch-all)
  const referencePath = path.resolve(__dirname, "..", "..", "reference");
  if (fs.existsSync(referencePath)) {
    app.use("/reference", express.static(referencePath));
  }

  const vite = await import("vite");

  const viteDevServer = await vite.createServer({
    configFile: path.resolve(__dirname, "../vite.config.ts"),
    server: {
      middlewareMode: true,
      hmr: {
        server,
      },
      watch: {
        usePolling: true,
        interval: 300000,
      },
    },
    appType: "custom",
  });

  app.use(viteDevServer.middlewares);

  // Log HMR updates so we can detect spurious reloads during E2E tests
  viteDevServer.ws.on('connection', (socket: any) => {
    const origSend = socket.send?.bind(socket);
    if (origSend) {
      socket.send = (data: any, ...args: any[]) => {
        try {
          const msg = typeof data === 'string' ? JSON.parse(data) : data;
          if (msg?.type === 'update' || msg?.type === 'full-reload') {
            console.log(`[ViteHMR] ${msg.type} at ${new Date().toISOString()}: ${JSON.stringify(msg).slice(0, 200)}`);
          }
        } catch {}
        return origSend(data, ...args);
      };
    }
  });

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
  // Check if we are running from source (e.g. tsx server/index.ts) or built (node dist/index.js)
  // In source, __dirname is .../frontend/server
  // In build, __dirname is .../frontend/dist
  const isRunningFromSource = __dirname.endsWith("server");
  const distPath = isRunningFromSource
    ? path.resolve(__dirname, "..", "dist", "public")
    : path.resolve(__dirname, "public");

  if (!fs.existsSync(distPath)) {
    throw new Error(
      `Could not find static assets at ${distPath}. Please run 'npm run build'.`
    );
  }

  const indexPath = path.join(distPath, "index.html");

  // Serve static assets
  app.use(express.static(distPath));

  // Serve reference design prototypes as static files (demo / design-review use)
  const referencePath = path.resolve(__dirname, "..", "..", "reference");
  if (fs.existsSync(referencePath)) {
    app.use("/reference", express.static(referencePath));
  }

  // Serve index.html for all non-API routes (SPA fallback)
  app.get("*", (req, res) => {
    if (req.path.startsWith("/api")) {
      return res.status(404).json({
        error: "NotFound",
        message: `API route ${req.path} not found`,
      });
    }
    res.sendFile(indexPath);
  });
}

/**
 * Logger utility
 */
export function log(...args: any[]) {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}]`, ...args);
}
