// @vitest-environment node
/**
 * S5 (audit 2026-11-12): the generic /api/perception/* proxy authorizes ONE ref (datasetRef), so
 * it must not forward anything else that names data — folder_profile's files[].datasetRef read
 * any path / S3 key, and the backend also accepts `dataset_ref`. Behaviour of the gate over
 * loopback HTTP (a request it refuses never reaches the next handler = the backend proxy), plus
 * the wiring in routes.ts (gate mounted before the access check on both perception routes).
 */
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import express from "express";
import type { Server } from "http";
import type { AddressInfo } from "net";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { gatePerceptionRequest, perceptionProxyGate } from "./perception-proxy-gate";

const httpFetch = globalThis.fetch;
const HERE = path.dirname(fileURLToPath(import.meta.url));
const forwarded = vi.fn();
let server: Server;
let base = "";

beforeAll(async () => {
  const app = express();
  app.use(express.json());
  app.all("/api/perception/*", perceptionProxyGate, (req, res) => { forwarded(req.path, req.body); res.json({ ok: true }); });
  await new Promise<void>((r) => { server = app.listen(0, "127.0.0.1", () => r()); });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});
afterAll(() => server?.close());
beforeEach(() => forwarded.mockClear());

const post = (p: string, body: unknown) =>
  httpFetch(`${base}${p}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

describe("perception proxy gate", () => {
  it("folder_profile is not reachable through the generic proxy (files[] pointing anywhere)", async () => {
    const r = await post("/api/perception/folder_profile", {
      path: "", files: [{ name: "x", datasetRef: "/etc/passwd" }, { name: "y", datasetRef: "projects/OTHER/inputs/secret.csv" }],
    });
    expect(r.status).toBe(404);
    expect(forwarded).not.toHaveBeenCalled();
  });

  it("refuses extra ref-carrying fields on profile/rows (files[], dataset_ref) — 400, not forwarded", async () => {
    const a = await post("/api/perception/profile", { datasetRef: "projects/p/inputs/a.csv", files: [{ name: "x", datasetRef: "/etc/passwd" }] });
    expect(a.status).toBe(400);
    expect(await a.json()).toEqual({ error: "unexpected_fields", fields: ["files"] });
    const b = await post("/api/perception/rows", { dataset_ref: "/etc/passwd" });
    expect(b.status).toBe(400);
    expect(forwarded).not.toHaveBeenCalled();
  });

  it("forwards the allowlisted body only; a client folderContext is dropped (the server attaches its own)", async () => {
    const r = await post("/api/perception/profile", { datasetRef: "projects/p/inputs/a.csv", name: "a.csv", folderContext: { name: "evil", siblings: ["/etc"] } });
    expect(r.status).toBe(200);
    expect(forwarded).toHaveBeenCalledWith("/api/perception/profile", { datasetRef: "projects/p/inputs/a.csv", name: "a.csv" });
    const rows = await post("/api/perception/rows", { datasetRef: "projects/p/inputs/a.csv", offset: 0, limit: 50 });
    expect(rows.status).toBe(200);
    expect(forwarded).toHaveBeenLastCalledWith("/api/perception/rows", { datasetRef: "projects/p/inputs/a.csv", offset: 0, limit: 50 });
  });

  it("other paths 404, GET 405, non-object bodies 400", () => {
    expect(gatePerceptionRequest("POST", "/api/perception/anything", {})).toMatchObject({ ok: false, status: 404 });
    expect(gatePerceptionRequest("GET", "/api/perception/profile", {})).toMatchObject({ ok: false, status: 405 });
    expect(gatePerceptionRequest("POST", "/api/perception/profile", [1])).toMatchObject({ ok: false, status: 400 });
  });
});

describe("routes.ts wiring", () => {
  const src = fs.readFileSync(path.join(HERE, "routes.ts"), "utf8");
  it("both perception routes run the gate before the dataset access check and the proxy", () => {
    expect(src).toMatch(/app\.post\("\/api\/perception\/profile", authenticateToken, perceptionProxyGate, requireDatasetAccess\(\), attachFolderContext, recordProfile, _dlProxyHandler\)/);
    expect(src).toMatch(/app\.all\("\/api\/perception\/\*", authenticateToken, perceptionProxyGate, requireDatasetAccess\(\), attachFolderContext, _dlProxyHandler\)/);
    // no other route proxies /api/perception
    expect((src.match(/"\/api\/perception/g) ?? []).length).toBe(2);
  });
});
