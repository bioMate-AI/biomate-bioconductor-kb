import { describe, expect, it, vi } from "vitest";
import { decideRunAccess } from "./run-access";

const ownedRun = { userId: "owner-1", projectId: null };

/** Every exposed run-data surface relies on this same decision policy. */
const protectedSurfaces = [
  "/api/runs/:anyId/outputs",
  "/api/runs/:anyId/meta",
  "/api/workflows/runs/:id/output_files",
  "/api/workflows/runs/:id/outputs",
  "/api/workflows/runs/:id/findings",
  "/api/workflows/runs/:id/findings/report",
  "/api/runs/:runId/output/:filename",
];

describe.each(protectedSurfaces)("run access policy: %s", (surface) => {
  it("returns 401 without an authenticated user", async () => {
    await expect(decideRunAccess(ownedRun, null)).resolves.toMatchObject({
      allowed: false,
      status: 401,
    });
  });

  it("returns 403 for a different user outside the project", async () => {
    const projects = vi.fn().mockResolvedValue([]);
    await expect(decideRunAccess(ownedRun, "other-user", projects)).resolves.toMatchObject({
      allowed: false,
      status: 403,
    });
  });

  it("allows the run owner", async () => {
    await expect(decideRunAccess(ownedRun, "owner-1")).resolves.toEqual({
      allowed: true,
      via: "owner",
    });
  });
});

describe("run access policy: project sharing", () => {
  it("allows a member of the run project, but fails closed when membership cannot be verified", async () => {
    const run = { userId: "owner-1", projectId: "project-a" };
    await expect(
      decideRunAccess(run, "member-2", vi.fn().mockResolvedValue([{ id: "project-a" }])),
    ).resolves.toEqual({ allowed: true, via: "project_member" });
    await expect(
      decideRunAccess(run, "member-2", vi.fn().mockRejectedValue(new Error("database unavailable"))),
    ).resolves.toMatchObject({ allowed: false, status: 403 });
  });
});
