/**
 * B3 — Per-org retrain queue route trust matrix.
 *
 *   R1 list (empty or array)
 *   R2 count returns {count:N}
 *   R3 submit → 201 + queued
 *   R4+R5 get by id (owner-scoped) + list shows it
 *   R6 unauthenticated → 401
 */
import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login.js";

test.describe("Retrain job routes (B3)", () => {
  test("R1 list (empty or array)", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/regulatory_llm/training_jobs`, {
        credentials: "include",
      });
      return { status: r.status, body: await r.json().catch(() => null) };
    }, BASE_URL);
    expect(r.status).toBe(200);
    expect(Array.isArray(r.body)).toBe(true);
  });

  test("R2 edit_pairs/count returns numeric count", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/regulatory_llm/edit_pairs/count`, {
        credentials: "include",
      });
      return { status: r.status, body: await r.json().catch(() => null) };
    }, BASE_URL);
    expect(r.status).toBe(200);
    expect(typeof r.body?.count).toBe("number");
  });

  test("R3 submit → 201 + queued status", async ({ page }) => {
    await loginAsFixture(page);
    const r = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/regulatory_llm/training_jobs`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({}),
      });
      return { status: r.status, body: await r.json().catch(() => null) };
    }, BASE_URL);
    expect(r.status).toBe(201);
    expect(r.body?.status).toBe("queued");
    expect(typeof r.body?.job_id).toBe("string");
    expect(r.body.job_id.length).toBeGreaterThan(16);
  });

  test("R4+R5 get by id (owner-scoped) + list contains it", async ({ page }) => {
    await loginAsFixture(page);
    const submitted = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/regulatory_llm/training_jobs`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({}),
      });
      return await r.json();
    }, BASE_URL);
    const jobId = submitted?.job_id;
    expect(jobId).toBeTruthy();

    const got = await page.evaluate(
      async ({ base, jobId }) => {
        const r = await fetch(
          `${base}/api/regulatory_llm/training_jobs/${jobId}`,
          { credentials: "include" }
        );
        return { status: r.status, body: await r.json().catch(() => null) };
      },
      { base: BASE_URL, jobId }
    );
    expect(got.status).toBe(200);
    expect(got.body?.job_id).toBe(jobId);

    const list = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/regulatory_llm/training_jobs`, {
        credentials: "include",
      });
      return await r.json();
    }, BASE_URL);
    expect(list.find((j: any) => j.job_id === jobId)).toBeTruthy();
  });

  test("R6 unauthenticated → 401", async ({ page }) => {
    await page.goto(BASE_URL);
    const r = await page.evaluate(async (base) => {
      const r = await fetch(`${base}/api/regulatory_llm/training_jobs`);
      return r.status;
    }, BASE_URL);
    expect([401, 403]).toContain(r);
  });
});
