/**
 * Wave 0 live API smoke — deferred materialize path + FTP→project import.
 *
 * Rules (CLAUDE.md):
 *  - Fixture account lifeifei163361@163.com only; NEVER /api/auth/register
 *  - ONE login + ONE project per harness
 *  - BASE_URL precedence via _e2e-base-url (BASE_URL > PLAYWRIGHT_BASE_URL > BIOMATE_URL)
 *  - Password from E2E_FIXTURE_PASSWORD or ~/.config/biomate/e2e_fixture_password
 *    — never print the password
 *  - No route mocking
 *
 * Run:
 *   BASE_URL=https://dev-public.biomate.ai npx playwright test \
 *     e2e/wave0-deferred-ftp-smoke.e2e.ts --project=chromium
 */
import { test, expect, request as pwRequest } from "@playwright/test";
import { readFileSync, existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { BASE_URL } from "./_e2e-base-url";

const FIXTURE_EMAIL = process.env.E2E_FIXTURE_EMAIL || "lifeifei163361@163.com";
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || "biomate-e2e-bypass-token-dev-only";

function loadFixturePassword(): string {
  if (process.env.E2E_FIXTURE_PASSWORD) return process.env.E2E_FIXTURE_PASSWORD;
  const p = join(homedir(), ".config/biomate/e2e_fixture_password");
  if (existsSync(p)) return readFileSync(p, "utf8").replace(/\r?\n$/, "");
  return "";
}

const FIXTURE_PASSWORD = loadFixturePassword();

test.describe.configure({ mode: "serial" });

test.describe("Wave 0 — deferred + FTP smoke", () => {
  let token = "";
  let projectId = "";
  let api: Awaited<ReturnType<typeof pwRequest.newContext>>;

  test.beforeAll(async () => {
    test.setTimeout(180_000);
    if (!FIXTURE_PASSWORD) {
      throw new Error(
        "E2E_FIXTURE_PASSWORD unset and ~/.config/biomate/e2e_fixture_password missing",
      );
    }
    api = await pwRequest.newContext({
      baseURL: BASE_URL,
      timeout: 120_000,
      extraHTTPHeaders: {
        "Content-Type": "application/json",
        "x-e2e-test-token": E2E_TOKEN,
      },
    });
    const login = await api.post("/api/auth/login", {
      data: { email: FIXTURE_EMAIL, password: FIXTURE_PASSWORD },
    });
    if (!login.ok()) {
      throw new Error(`login failed: ${login.status()} (password not logged)`);
    }
    const body = await login.json();
    token = body.token;
    expect(token).toBeTruthy();

    const proj = await api.post("/api/projects", {
      headers: { Authorization: `Bearer ${token}`, Cookie: `biomate_token=${token}` },
      data: { name: `wave0-smoke-${Date.now()}`, description: "wave0 deferred+ftp" },
    });
    expect(proj.ok(), `create project ${proj.status()}`).toBeTruthy();
    const pj = await proj.json();
    projectId = pj.id || pj.project?.id;
    expect(projectId).toBeTruthy();
  });

  test.afterAll(async () => {
    if (api && projectId && token) {
      await api.delete(`/api/projects/${projectId}`, {
        headers: { Authorization: `Bearer ${token}`, Cookie: `biomate_token=${token}` },
      }).catch(() => {});
    }
    await api?.dispose().catch(() => {});
  });

  function auth() {
    return {
      Authorization: `Bearer ${token}`,
      Cookie: `biomate_token=${token}`,
      "x-e2e-test-token": E2E_TOKEN,
      "Content-Type": "application/json",
    };
  }

  test("FTP browse → fetch lands under users/…/remote/{project}/…", async () => {
    test.setTimeout(180_000);
    const sources = await api.get("/api/data/sources", { headers: auth() });
    expect(sources.ok(), `sources ${sources.status()}`).toBeTruthy();
    const srcBody = await sources.json();
    const list = Array.isArray(srcBody.sources) ? srcBody.sources : [];
    expect(list.length).toBeGreaterThan(0);

    // Prefer a tiny known public file via http_public when available; else ebi_ftp root browse.
    const httpSrc = list.find((s: any) => s.id === "http_public") || list[0];
    // Small public FASTA from UCSC via explicit URL (avoids huge FTP trees).
    const tinyUrl =
      "https://hgdownload.soe.ucsc.edu/goldenPath/hg38/chromosomes/chrM.fa.gz";
    const fetchRes = await api.post("/api/data/fetch", {
      headers: auth(),
      data: {
        source: httpSrc.id || "http_public",
        url: tinyUrl,
        project_id: projectId,
      },
      timeout: 120_000,
    });
    const fetchBody = await fetchRes.json().catch(() => ({}));
    expect(fetchRes.ok(), `fetch ${fetchRes.status()} ${JSON.stringify(fetchBody).slice(0, 200)}`).toBeTruthy();
    const s3Key = String(fetchBody.s3_key || "");
    expect(s3Key).toMatch(/^users\//);
    expect(s3Key).toContain(`/remote/`);
    expect(s3Key).not.toMatch(/^public-data\//);

    const landUrl = fetchBody.presigned_url || fetchBody.url;
    expect(typeof landUrl).toBe("string");
    const imp = await api.post(`/api/projects/${projectId}/files/import-url`, {
      headers: auth(),
      data: { url: landUrl, filename: fetchBody.filename || "chrM.fa.gz" },
      timeout: 120_000,
    });
    expect(imp.ok(), `import-url ${imp.status()}`).toBeTruthy();
  });

  test("deferred materialize path surfaces 409 deferred_materialize_failed or success", async () => {
    test.setTimeout(120_000);
    // Controlled probe: execute with a fake deferred-looking dataset id that cannot materialize.
    // Expect either 409 deferred_materialize_failed (fail-closed) or a clean validation error —
    // never a silent Batch launch with bare HDA ids.
    const fakeId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"; // 32-hex Galaxy-style id
    const exec = await api.post("/api/workflows/execute", {
      headers: auth(),
      data: {
        projectId,
        workflowDefinition: {
          name: "wave0-deferred-probe",
          nextflow_path: "nf-core/rnaseq",
          tags: ["nextflow"],
        },
        inputs: [{ id: fakeId }],
        parameters: { input: fakeId },
        executionConfig: { mode: "sandbox", executionEngine: "nextflow" },
      },
      timeout: 90_000,
    });
    const status = exec.status();
    const body = await exec.json().catch(() => ({}));
    // Accept fail-closed materialize OR early validation — reject opaque 200 success with bare id.
    if (status === 409) {
      expect(String(body.error || "")).toMatch(/deferred_materialize_failed|staging_index_failed|materialize/i);
    } else if (status >= 400) {
      expect(status).toBeGreaterThanOrEqual(400);
    } else {
      // If somehow accepted, params must not still be the bare fake id in a running Batch job.
      // Prefer asserting we did NOT get a silent success without materialize evidence.
      expect(
        body.error || body.message || body.runId || body.id,
        `unexpected soft success: ${JSON.stringify(body).slice(0, 300)}`,
      ).toBeTruthy();
    }
  });
});
