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
        usePolling: false,
        ignored: [
          "**/dist/**",
          "**/e2e/test-results/**",
          "**/e2e/screenshots/**",
          "**/e2e/reports/**",
          "**/playwright-report/**",
        ],
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

  serveStaticDirectory(app, distPath, indexPath);
}

/** Production static serving, with an explicit asset directory for reuse/tests. */
export function serveStaticDirectory(app: Express, distPath: string, indexPath = path.join(distPath, "index.html")) {
  const disableGoogle = process.env.DISABLE_GOOGLE_FONTS === "true" || process.env.VITE_ONPREM === "true";

  // Register before express.static: otherwise / and /index.html bypass the
  // filtering handler through static middleware's automatic index response.
  if (disableGoogle) {
    const sendFilteredIndex = (_req: express.Request, res: express.Response, next: express.NextFunction) => {
      fs.readFile(indexPath, "utf-8", (error, html) => {
        if (error) return next(error); // no fallback to the unfiltered document
        html = html.replace(/<link\b[^>]*(?:fonts\.googleapis\.com|fonts\.gstatic\.com)[^>]*>/gi, "")
          .replace(/<script\b[^>]*googletagmanager\.com[^>]*>[\s\S]*?<\/script\s*>/gi, "")
          .replace(/<script\b[^>]*>\s*window\.dataLayer[\s\S]*?<\/script\s*>/gi, "");
        res.set("Cache-Control", "no-store").type("html").send(html);
      });
    };
    app.use((req, res, next) => {
      let pathname: string;
      try { pathname = path.posix.normalize(decodeURIComponent(req.path)); }
      catch { return res.status(400).end(); }
      if ((req.method === "GET" || req.method === "HEAD") && (pathname === "/" || pathname === "/index.html")) {
        return sendFilteredIndex(req, res, next);
      }
      return next();
    });
    app.use(express.static(distPath, { index: false }));
    app.get("*", (req, res, next) => {
      if (req.path.startsWith("/api")) return res.status(404).json({ error: "NotFound" });
      return sendFilteredIndex(req, res, next);
    });
    return;
  }

  app.use(express.static(distPath));
  // Design prototypes are development-only (setupVite), not release assets.

  // Serve index.html for all non-API routes (SPA fallback)
  app.get("*", (req, res) => {
    if (req.path.startsWith("/api")) {
      return res.status(404).json({
        error: "NotFound",
        message: `API route ${req.path} not found`,
      });
    }
    // On-prem / China deployment: strip Google CDN links that hang behind GFW.
    // Triggered by DISABLE_GOOGLE_FONTS=true or VITE_ONPREM=true in .env.
    if (process.env.DISABLE_GOOGLE_FONTS === "true" || process.env.VITE_ONPREM === "true") {
      try {
        let html = fs.readFileSync(indexPath, "utf-8");
        // Remove Google Fonts preconnect + stylesheet links
        html = html.replace(/<link[^>]*fonts\.googleapis\.com[^>]*>/g, "");
        html = html.replace(/<link[^>]*fonts\.gstatic\.com[^>]*>/g, "");
        // Remove Google Analytics / Tag Manager script tags
        html = html.replace(/<script[^>]*googletagmanager\.com[^>]*><\/script>/g, "");
        html = html.replace(/<script[^>]*>\s*window\.dataLayer[\s\S]*?<\/script>/g, "");
        return res.set("Content-Type", "text/html").send(html);
      } catch {
        // Fall through to sendFile if read fails
      }
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
