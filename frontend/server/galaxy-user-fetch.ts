/**
 * fetch() to Galaxy as the signed-in user, for routes that call Galaxy directly instead of
 * through a GalaxyAPIProxy: the user's own Galaxy key (else the shared admin key) plus the
 * same mid-session key recovery as userProxy() (see fetchGalaxyWithKeyRecovery).
 *
 * Shared by routes.ts (backend passthroughs) and project-routes.ts (paged dataset rows), so
 * every direct Galaxy call carries the same key choice.
 */
import type { Request } from "express";
import { fetchGalaxyWithKeyRecovery } from "./galaxy-api-proxy";
import { authService } from "./auth-service";
import { decryptField } from "./field-encrypt";

export function fetchGalaxyAsUser(req: Request, url: string, init: RequestInit = {}): Promise<Response> {
  const user = req.user as any;
  const raw = user?.galaxyApiKey as string | undefined;
  const recover = user?.id && user?.email
    ? () => authService.recoverGalaxyKey(String(user.id), String(user.email))
    : undefined;
  return fetchGalaxyWithKeyRecovery(url, init, raw ? decryptField(raw) : null, process.env.GALAXY_API_KEY || "", recover);
}

export function galaxyBaseUrl(): string {
  return process.env.GALAXY_URL || "http://localhost:8081";
}
