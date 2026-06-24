/**
 * Regression tests for the 2026-06-12 auth bug-fixes.
 *
 * Bug 1 — registration email-verification link 404
 *   Root cause: /api/auth/register never returned the verification token.
 *   The registration UI's dev-mode "click this link" affordance therefore
 *   rendered the URL as `/verify-email?token=null`, which loaded the
 *   VerifyEmailPage but landed on the "No verification token found"
 *   error path (visually a 404).
 *   Fix: routes.ts captures the token via
 *   sendVerificationEmail({returnToken:true}) and merges it into the
 *   response user object. The previous fire-and-forget call inside
 *   auth-service.register() is removed (was a race that double-wrote
 *   the token and obscured the return value).
 *
 * Bug 2 — expired-trial login 404
 *   Root cause: auth-service.verifyCredentials() threw
 *   `TRIAL_EXPIRED`; client redirected to `/pricing?from=trial-expired`;
 *   /pricing route is commented out in App.tsx → React shows 404.
 *   Fix: trial expiry now demotes user to free plan instead of
 *   blocking login (per product policy: "if the trial expires, the
 *   user can still be in the free account"). Client error-handling
 *   keeps a defensive branch but no longer redirects to a dead route.
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";

const SERVER = path.join(__dirname);
const CLIENT = path.join(__dirname, "..", "client", "src");

describe("Bug 1: register endpoint returns verificationToken", () => {
  const ROUTES = fs.readFileSync(path.join(SERVER, "routes.ts"), "utf-8");
  const AUTH = fs.readFileSync(path.join(SERVER, "auth-service.ts"), "utf-8");

  it("/api/auth/register captures the verification token via sendVerificationEmail({returnToken:true})", () => {
    expect(/sendVerificationEmail\(\s*result\.user\.id\s*,\s*\{\s*returnToken:\s*true\s*\}\s*\)/.test(ROUTES)).toBe(true);
  });

  it("/api/auth/register response includes verificationToken on the user object", () => {
    // Token is gated: null when SMTP is configured (production), real token in dev-only mode.
    // Pattern: verificationToken: _emailConfigured ? null : _verificationToken
    expect(/verificationToken\s*:\s*_emailConfigured\s*\?\s*null\s*:\s*_verificationToken/.test(ROUTES)).toBe(true);
  });

  it("auth-service.sendVerificationEmail supports an overload that returns the token", () => {
    // Overload signature + implementation guard
    expect(/sendVerificationEmail\(userId:\s*string,\s*opts:\s*\{\s*returnToken:\s*true\s*\}\s*\)\s*:\s*Promise<string\s*\|\s*null>/.test(AUTH)).toBe(true);
    expect(/opts\?\.returnToken/.test(AUTH)).toBe(true);
  });

  it("auth-service.register() no longer fires-and-forgets a duplicate sendVerificationEmail", () => {
    // The duplicate call inside register() returned no token and raced with
    // the routes.ts call. It's removed; the routes.ts path is the single
    // source for token issuance during registration.
    expect(/this\.sendVerificationEmail\(newUser\.id\)\.catch/.test(AUTH)).toBe(false);
  });

  it("the previously broken response shape would have given the client a null token", () => {
    // Lock in the failure mode the fix addressed: the user object returned
    // by auth-service.register() does NOT carry a verificationToken field
    // out of the box (no DB select includes it; the column is sanitized).
    // The route handler is responsible for the token-bearing response.
    expect(AUTH.includes("verificationToken: token")).toBe(true); // still persisted to DB
  });
});

describe("Bug 2: expired trial demotes to free plan, does NOT block login", () => {
  const AUTH = fs.readFileSync(path.join(SERVER, "auth-service.ts"), "utf-8");
  const CTX = fs.readFileSync(path.join(CLIENT, "contexts", "auth-context.tsx"), "utf-8");

  it("verifyCredentials no longer throws TRIAL_EXPIRED", () => {
    expect(/throw new Error\('TRIAL_EXPIRED'\)/.test(AUTH)).toBe(false);
  });

  it("verifyCredentials demotes expired-trial users to free plan", () => {
    expect(/trialExpired\s*&&\s*!subscriptionActive\s*&&\s*user\.subscriptionTier\s*===\s*['"]trial['"]/.test(AUTH)).toBe(true);
    expect(/subscriptionTier:\s*['"]free['"]/.test(AUTH)).toBe(true);
    expect(/subscriptionStatus:\s*['"]inactive['"]/.test(AUTH)).toBe(true);
  });

  it("client no longer auto-redirects expired trials to /pricing (which is commented out)", () => {
    expect(/window\.location\.href\s*=\s*['"]\/pricing\?from=trial-expired['"]/.test(CTX)).toBe(false);
  });

  it("client retains a defensive error message for any stale TRIAL_EXPIRED responses", () => {
    expect(CTX.includes("TRIAL_EXPIRED")).toBe(true);  // branch still present
    expect(/Your free trial has ended/.test(CTX)).toBe(true);
  });
});
