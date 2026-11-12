// @vitest-environment node
/**
 * NEW-3 (2026-11-12 round-2 audit) — every passthrough forwards only a path under its own
 * prefix. On c4bfb9fd8c `/api/generate/../perception/folder_profile` and
 * `/api/generate/%2e%2e/perception/profile` (optionalAuth: anonymous callers, shared
 * GALAXY_API_KEY) reached the backend as /api/perception/* with the caller's body.
 *
 * Real express + a real HTTP "Galaxy" that records what it receives; requests are sent with
 * http.request so the path goes out un-normalised (curl --path-as-is). Only ./galaxy-user-fetch
 * is faked (a plain fetch — its key choice is not under test here).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import express from "express";
import http from "http";
import type { AddressInfo } from "net";
import { readFileSync } from "fs";
import path from "path";
import { confineProxyPath, routePrefix } from "./proxy-path";

vi.mock("./galaxy-user-fetch", () => ({
  fetchGalaxyAsUser: (_req: any, url: string, init: RequestInit) => fetch(url, init),
  galaxyBaseUrl: () => process.env.GALAXY_URL,
}));

const seen: string[] = [];
let galaxy: http.Server;
let app: http.Server;
let port = 0;

beforeAll(async () => {
  galaxy = http.createServer((q, s) => {
    let b = "";
    q.on("data", (c) => (b += c));
    q.on("end", () => { seen.push(`${q.method} ${q.url} ${b}`); s.setHeader("content-type", "application/json"); s.end('{"ok":true}'); });
  });
  await new Promise<void>((r) => galaxy.listen(0, "127.0.0.1", () => r()));
  process.env.GALAXY_URL = `http://127.0.0.1:${(galaxy.address() as AddressInfo).port}`;

  const { backendPassthrough } = await import("./backend-passthrough");
  const e = express();
  e.use(express.json());
  const dl = backendPassthrough("DL surface");
  // Mounted exactly as routes.ts mounts them (the generate prefixes are optionalAuth there).
  e.all("/api/generate", dl);
  e.all("/api/generate/*", dl);
  e.all("/api/datasets/*", dl);
  e.all("/api/route/*", dl);
  e.all("/api/perception/*", (_q, res) => res.status(418).json({ gated: true }));
  await new Promise<void>((r) => { app = e.listen(0, "127.0.0.1", () => r()); });
  port = (app.address() as AddressInfo).port;
});
afterAll(() => { app?.close(); galaxy?.close(); });
beforeEach(() => { seen.length = 0; });

function raw(method: string, p: string, body?: unknown): Promise<{ status: number; body: any }> {
  return new Promise((resolve, reject) => {
    const data = body === undefined ? undefined : JSON.stringify(body);
    const rq = http.request({
      host: "127.0.0.1", port, path: p, method,
      headers: data ? { "content-type": "application/json", "content-length": Buffer.byteLength(data) } : {},
    }, (rs) => {
      let d = "";
      rs.on("data", (c) => (d += c));
      rs.on("end", () => resolve({ status: rs.statusCode || 0, body: d ? JSON.parse(d) : null }));
    });
    rq.on("error", reject);
    rq.end(data);
  });
}

const VICTIM = { projectId: "victim", files: [{ name: "matrix.mtx", datasetRef: "projects/victim/inputs/matrix.mtx" }] };

describe("backendPassthrough — path stays under its prefix", () => {
  const attacks = [
    "/api/generate/../perception/folder_profile",
    "/api/generate/%2e%2e/perception/profile",
    "/api/generate/%2E%2E/perception/profile",
    "/api/generate/.%2e/perception/profile",
    "/api/generate/x/..%2f..%2fperception%2fprofile",
    "/api/generate/x%2f..%2f..%2fperception/profile",
    "/api/generate/%252e%252e/perception/profile",
    "/api/generate/%25252e%25252e/perception/profile",
    "/api/generate/..%5c..%5cperception/profile",
    "/api/generate/x/./y",
    "/api/datasets/projects%2Fvictim%2F..%2F..%2Fother/lineage",
    "/api/route/%2e%2e%2fperception/profile",
  ];
  for (const p of attacks) {
    it(`refuses ${p} (400) and the backend sees nothing`, async () => {
      const r = await raw("POST", p, VICTIM);
      expect(r.status).toBe(400);
      expect(r.body.error).toBe("invalid_path");
      expect(seen).toEqual([]);
    });
  }

  it("forwards a normal generate request unchanged (path, query and body)", async () => {
    const r = await raw("POST", "/api/generate/run-1?project=p1&x=%2e%2e", { a: 1 });
    expect(r.status).toBe(200);
    expect(seen).toEqual(['POST /api/generate/run-1?project=p1&x=%2e%2e {"a":1}']);
  });

  it("forwards the exact prefix route", async () => {
    const r = await raw("POST", "/api/generate", { a: 2 });
    expect(r.status).toBe(200);
    expect(seen).toEqual(['POST /api/generate {"a":2}']);
  });

  it("keeps URL-encoded dataset refs (encoded slashes inside one segment are not traversal)", async () => {
    const r = await raw("GET", "/api/datasets/projects%2Fp1%2Finputs%2F50%25.csv/lineage");
    expect(r.status).toBe(200);
    expect(seen).toEqual(["GET /api/datasets/projects%2Fp1%2Finputs%2F50%25.csv/lineage "]);
  });
});

describe("confineProxyPath / routePrefix", () => {
  it("accepts only paths under the prefix", () => {
    expect(confineProxyPath("/api/generate/x?y=1", "/api/generate")).toEqual({ ok: true, path: "/api/generate/x", query: "?y=1" });
    expect(confineProxyPath("/api/generateX", "/api/generate").ok).toBe(false);
    expect(confineProxyPath("/api/perception/profile", "/api/generate").ok).toBe(false);
    expect(confineProxyPath("/api/generate/a\\b", "/api/generate").ok).toBe(false);
    expect(confineProxyPath("/api/generate/a%00b", "/api/generate").ok).toBe(false);
    expect(confineProxyPath("/api/generate/a%2561", "/api/generate").ok).toBe(true); // no dot segment at any depth
  });
  it("derives the literal prefix of the matched route", () => {
    expect(routePrefix({ route: { path: "/api/generate/*" } })).toBe("/api/generate");
    expect(routePrefix({ route: { path: "/oauth/tools/:name" } })).toBe("/oauth/tools");
    expect(routePrefix({ route: { path: "/mcp" } })).toBe("/mcp");
    expect(routePrefix({ route: { path: /^\/x/ } })).toBe(null);
  });
});

describe("routes.ts — no passthrough forwards the raw request path", () => {
  // Class guard: every proxy in routes.ts takes its forwarded path from proxyTarget() (the
  // inline drug-discovery / billing / qc-gates / models / MCP proxies are not mountable in a
  // unit test without the whole routes module). A new `${req.path}` forward fails here.
  const SRC = readFileSync(path.join(__dirname, "routes.ts"), "utf8");
  it("no URL is built from req.path / req.url", () => {
    expect(SRC).not.toMatch(/\$\{\s*(?:galaxyUrl|GALAXY_URL|galaxyBaseUrl\(\))\s*\}\$\{\s*req\.(?:path|url|originalUrl)/);
    expect(SRC).not.toMatch(/fetchOwnedModelSurface\([^)]*req\.(?:path|url)/);
    expect(SRC).not.toMatch(/new URL\(req\.(?:url|originalUrl)\s*,\s*MCP_UPSTREAM/);
    expect(SRC).not.toMatch(/const path = req\.path;/);
    expect((SRC.match(/proxyTarget\(req/g) ?? []).length).toBeGreaterThanOrEqual(6);
  });
});
