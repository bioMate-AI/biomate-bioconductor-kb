// Stub for the regulatory training routes (Lane B3 — per-org adapter retrain queue).
// The real implementation has not landed yet; the routes.ts importer (cd08a6554)
// referenced this module before it existed, breaking the build. This stub is a
// no-op registrar so the rest of the app can boot. Replace with the real
// implementation when ready — see the routes.ts:1239 caller.
import type { Express } from "express";

export function registerRegulatoryTrainingRoutes(app: Express): void {
  void app;
  console.warn(
    "[regulatory-training-routes] stub registrar — real implementation not yet committed",
  );
}
