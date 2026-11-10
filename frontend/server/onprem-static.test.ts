// @vitest-environment node
import { afterEach, describe, expect, it } from "vitest";
import express from "express";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import type { Server } from "node:http";
import { serveStaticDirectory } from "./vite";

const servers: Server[] = [];
const directories: string[] = [];
const previous = process.env.DISABLE_GOOGLE_FONTS;
afterEach(async () => {
  await Promise.all(servers.splice(0).map(server => new Promise<void>((resolve, reject) => {
    if (!server.listening) return resolve();
    server.close(error => error ? reject(error) : resolve());
    server.closeAllConnections();
  })));
  for (const directory of directories.splice(0)) fs.rmSync(directory, { recursive: true });
  if (previous === undefined) delete process.env.DISABLE_GOOGLE_FONTS;
  else process.env.DISABLE_GOOGLE_FONTS = previous;
});

async function fixture(disabled: boolean) {
  process.env.DISABLE_GOOGLE_FONTS = String(disabled);
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "biomate-static-test-"));
  directories.push(directory);
  fs.writeFileSync(path.join(directory, "index.html"), '<!doctype html><link href="https://fonts.googleapis.com/css?family=X"><link href="https://fonts.gstatic.com"><script src="https://www.googletagmanager.com/gtag/js"></script><script>window.dataLayer = []; gtag("config", "test");</script><main>BioMate</main><script src="/app.js"></script>');
  fs.writeFileSync(path.join(directory, "app.js"), "window.biomate = true;");
  const app = express();
  serveStaticDirectory(app, directory);
  const server = app.listen(0, "127.0.0.1");
  servers.push(server);
  await new Promise<void>((resolve, reject) => {
    server.once("listening", resolve);
    server.once("error", reject);
  });
  const address = server.address();
  if (!address || typeof address === "string") throw new Error("No TCP address");
  return { base: `http://127.0.0.1:${address.port}`, directory };
}

describe("on-prem production HTML", () => {
  for (const route of ["/", "/index.html", "/projects/example", "/%69ndex.html", "/index%2ehtml"]) {
    it(`filters Google dependencies on ${route} through real Express middleware`, async () => {
      const { base } = await fixture(true);
      const response = await fetch(base + route);
      const html = await response.text();
      expect(response.status).toBe(200);
      expect(html).not.toMatch(/googleapis|gstatic|googletagmanager|dataLayer/);
      expect(html).toContain("<main>BioMate</main>");
      expect(html).toContain('src="/app.js"');
      expect(response.headers.get("cache-control")).toBe("no-store");
    });
  }
  it("preserves normal behavior when disabled", async () => {
    const { base } = await fixture(false);
    expect(await (await fetch(base + "/")).text()).toContain("fonts.googleapis.com");
  });
  it("serves JS unchanged and does not return HTML for unknown API routes", async () => {
    const { base } = await fixture(true);
    expect(await (await fetch(base + "/app.js")).text()).toBe("window.biomate = true;");
    expect((await fetch(base + "/api/not-a-route")).status).toBe(404);
  });
  it("fails instead of falling back to unfiltered HTML when index cannot be read", async () => {
    const { base, directory } = await fixture(true);
    fs.unlinkSync(path.join(directory, "index.html"));
    expect((await fetch(base + "/")).status).toBe(500);
  });
});
