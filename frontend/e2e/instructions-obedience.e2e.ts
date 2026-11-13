/**
 * E2E (dev, live, no mocks): project instructions are OBEYED, not just recalled.
 * Instruction-panel committee audit 2026-11-12 — the only prior live tests checked that a reply
 * mentions the research goal; nothing proved a rule changes a reply or a workflow parameter.
 *
 * One project (created here, deleted in teardown), three rules, real chat turns via the API:
 *   (a) plain answer ends with the exact tag a rule demands; control without the project does not;
 *   (b) a workflow request that names no genome/threshold gets GRCh38 (and FDR 0.01 where the
 *       workflow has a significance parameter) from the project rules.
 *
 * Run: E2E_FIXTURE_PASSWORD=$(cat ~/.config/biomate/e2e_fixture_password) \
 *      BIOMATE_URL=https://dev-public.biomate.ai npx playwright test e2e/instructions-obedience.e2e.ts --project=chromium
 */
import { test, expect, type APIRequestContext } from "@playwright/test";
import { randomUUID } from "crypto";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const RULES = [
  "End every reply with the exact final line: Ref-Tag: KX-7741",
  "Always use the GRCh38 human reference genome; never GRCh37/hg19.",
  "For differential expression use FDR (adjusted p) < 0.01 and |log2FC| >= 1.",
].join("\n");

async function chat(req: APIRequestContext, message: string, projectId?: string): Promise<any> {
  const r = await req.post(BASE_URL + "/api/chat/stream", {
    data: { message, stream: true, context: { ...(projectId ? { projectId } : {}), sessionId: `e2e-instr-${randomUUID()}`, uiLanguage: "en" } },
    timeout: 240_000,
  });
  expect(r.ok(), `chat HTTP ${r.status()}`).toBe(true);
  const text = await r.text();
  // SSE: the `final` event carries the whole reply payload.
  const blocks = text.split("\n\n");
  for (let i = blocks.length - 1; i >= 0; i--) {
    if (!/^event:\s*final/m.test(blocks[i])) continue;
    const data = blocks[i].split("\n").filter((l) => l.startsWith("data:")).map((l) => l.slice(5).trim()).join("\n");
    return JSON.parse(data);
  }
  throw new Error("no final event");
}

const replyText = (f: any) => String(f?.response ?? f?.message ?? "").trim();
/** Structured params the panel / execute path actually see — not reply prose. */
const allParams = (f: any): Record<string, unknown> => {
  const ga = f?.workflow?.workflow_ga || f?.workflow || {};
  const out: Record<string, unknown> = {
    ...(ga.parameters || {}),
    ...(ga.inline_parameters || {}),
    ...(f?.inlineParameters || {}),
    ...(f?.metadata?.inlineParameters || {}),
  };
  for (const p of [...(ga.required_params || []), ...(ga.optional_params || [])]) {
    if (!p?.name || out[p.name] !== undefined) continue;
    const v = p.value ?? p.default;
    if (v != null && String(v).trim() !== "") out[p.name] = v;
  }
  return out;
};

test("project instructions change replies and workflow parameters", async ({ page }) => {
  test.setTimeout(15 * 60 * 1000);
  await loginAsFixture(page);
  const req = page.request;
  const created = await req.post(BASE_URL + "/api/projects", { data: { name: `E2E-Instr-${Date.now()}`, researchGoal: RULES } });
  expect(created.ok(), `create project HTTP ${created.status()}`).toBe(true);
  const createdBody = await created.json();
  const project = createdBody?.project ?? createdBody;
  const pid = String(project.id);
  try {
    // (a) plain answer obeys the tag rule; control (no project) does not carry it
    const a = await chat(req, "In two sentences, what is a volcano plot?", pid);
    console.log("[a] tail:", replyText(a).slice(-160));
    expect(replyText(a)).toMatch(/Ref-Tag:\s*KX-7741\s*$/);
    const ctl = await chat(req, "In two sentences, what is a volcano plot?");
    expect(replyText(ctl)).not.toMatch(/KX-7741/);

    // (b) workflow parameters follow the rules although the message names neither
    const b = await chat(req, "Set up an RNA-seq differential expression analysis for my human paired-end samples, treated vs control.", pid);
    const params = allParams(b);
    console.log("[b] workflow:", b?.workflow?.workflow_ga?.name || b?.workflow?.name, "params:", JSON.stringify(params).slice(0, 600));
    const genome = Object.entries(params).find(([k]) => /genome|reference|assembly/i.test(k));
    expect(genome, "the workflow has a genome parameter").toBeTruthy();
    expect(String(genome![1])).toMatch(/GRCh38|hg38/i);
    const fdr = Object.entries(params).find(([k]) => /fdr|padj|alpha|q_?val|p_?adj/i.test(k));
    if (fdr) expect(Number(fdr[1])).toBeCloseTo(0.01, 5);
    else console.log("[b] note: this workflow exposes no significance-threshold parameter");
  } finally {
    await req.delete(BASE_URL + `/api/projects/${encodeURIComponent(pid)}`).catch(() => {});
  }
});
