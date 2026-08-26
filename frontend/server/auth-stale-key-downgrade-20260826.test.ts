/**
 * Regression test for the 2026-08-26 "stale→null galaxyApiKey downgrade" bug.
 *
 * Root cause (auth-service.ts verifyCredentials, stale-key branch):
 *   On login, if the stored galaxyApiKey failed the /api/users/current
 *   staleness probe, the code CLEARED the key to null in the DB and THEN
 *   called provisionGalaxyUser() to re-provision. provisionGalaxyUser()
 *   never throws — on failure it returns false and kicks off background
 *   retries. So when /internal/users/provision was down (e.g. after a
 *   sync_to_dev DB swap reset Galaxy's universe.sqlite), the user was left
 *   with a NULL key. Every subsequent per-user Galaxy op then 400s because
 *   userProxy(req) builds forUser(undefined): createHistory, interactive-
 *   tool launch, and uploads-as-HDA all fail. A transient probe blip could
 *   also falsely mark a GOOD key stale and null it.
 *
 * Fix: re-provision FIRST; only overwrite the stored credentials when it
 *   succeeds (provisionGalaxyUser persists on success). Keep the existing
 *   (possibly stale) key on failure — a stale key and a null key fail the
 *   same way, but the stale key preserves galaxyUserId for the next drift
 *   check and lets background retries recover the session.
 *
 * See docs/20260610_STALE_GALAXY_USER_DRIFT.md for the drift mechanism.
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const AUTH = fs.readFileSync(path.join(__dirname, "auth-service.ts"), "utf-8");

// Isolate the stale-key branch so assertions don't match unrelated
// `galaxyApiKey: null` usages elsewhere in the file (e.g. schema defaults).
function staleBranch(src: string): string {
  const start = src.indexOf("if (isStale) {");
  expect(start, "stale-key branch not found in auth-service.ts").toBeGreaterThan(-1);
  // The branch ends at the enclosing try's catch — grab a generous window.
  return src.slice(start, start + 1600);
}

describe("2026-08-26: login must not downgrade a stale galaxyApiKey to null", () => {
  const BRANCH = staleBranch(AUTH);

  it("no longer nulls galaxyApiKey inside the stale-key branch before re-provisioning", () => {
    // The old anti-pattern: db.update(...).set({ galaxyApiKey: null, ... }) in
    // the isStale branch. It must be gone — that's the downgrade this fixes.
    expect(/galaxyApiKey:\s*null/.test(BRANCH)).toBe(false);
    expect(/\.set\(\{\s*galaxyApiKey:\s*null/.test(BRANCH)).toBe(false);
  });

  it("captures the re-provision result rather than fire-and-forgetting it", () => {
    // We must branch on success/failure, so the return value has to be bound.
    expect(/const\s+reprovisioned\s*=\s*await\s+this\.provisionGalaxyUser\(/.test(BRANCH)).toBe(true);
  });

  it("keeps the existing key when re-provisioning fails", () => {
    expect(/if\s*\(\s*!reprovisioned\s*\)/.test(BRANCH)).toBe(true);
    // The failure branch must NOT clear credentials — it only logs.
    expect(/!reprovisioned[\s\S]*galaxyApiKey:\s*null/.test(BRANCH)).toBe(false);
  });

  it("still re-provisions on staleness (behavior preserved, just reordered)", () => {
    expect(/this\.provisionGalaxyUser\(user\.id,\s*user\.email\)/.test(BRANCH)).toBe(true);
  });
});
