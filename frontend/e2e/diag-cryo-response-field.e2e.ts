import { test, expect } from "@playwright/test";
import { loginAsFixture, BASE_URL } from "./_fixture-login";
const CRYO_QUERY = "Process this cryo-EM dataset to a density map and report the resolution.\n\nPrepared demo context:\nUse the already staged EMPIAR-10028 beta-galactosidase movies at s3://biomate-cryo-data/empiar-10028/Micrographs/ (001_movie.mrcs through 020_movie.mrcs). cryo_inputs.json provides acquisition settings: pixel size 0.885 Å, 300 kV, Cs 2.7 mm, amplitude contrast 0.1, symmetry D2, particle diameter 180 Å. Bind the staged movie prefix as the workflow input, not this manifest as a micrograph. Report observed QC/resolution honestly.";

function cut(v: any, n = 400): string {
  try { return JSON.stringify(v).slice(0, n); } catch { return String(v).slice(0, n); }
}
// Recursively find every path whose string value contains needle.
function findPaths(obj: any, needle: string, base = "$", out: string[] = []): string[] {
  if (out.length > 40) return out;
  if (typeof obj === "string") {
    if (obj.includes(needle)) out.push(`${base} = ${obj.slice(0, 220)}`);
    return out;
  }
  if (obj && typeof obj === "object") {
    for (const k of Object.keys(obj)) findPaths(obj[k], needle, `${base}.${k}`, out);
  }
  return out;
}

test("diag cryo response field carrying composite", async ({ page }) => {
  test.setTimeout(240000);
  const bodies: { url: string; text: string }[] = [];
  const respObjs: { url: string; resp: any }[] = [];
  page.on("response", (resp) => {
    const url = resp.url();
    if (url.includes("/api/chat")) respObjs.push({ url, resp });
  });
  const withTimeout = <T,>(p: Promise<T>, ms: number): Promise<T | null> =>
    Promise.race([p, new Promise<null>((r) => setTimeout(() => r(null), ms))]);

  await loginAsFixture(page);
  await page.setViewportSize({ width: 1600, height: 1200 });
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60000 });
  const input = page.getByTestId("chat-input");
  await input.waitFor({ state: "visible", timeout: 45000 }); await page.waitForTimeout(3000);
  const resp = await page.request.get(`${BASE_URL}/demo/cold-start/cryo_inputs.json`);
  const buffer = await resp.body();
  await page.locator('[data-testid="chat-attach-file-input"]').setInputFiles([{ name: "cryo_inputs.json", mimeType: "application/json", buffer }], { timeout: 30000 });
  await page.getByTestId("composer-attached-file").first().waitFor({ state: "visible", timeout: 20000 }).catch(() => {});
  await input.click(); await input.fill(CRYO_QUERY);
  const sr = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await sr.waitFor({ state: "visible", timeout: 30000 }); await sr.click();
  await page.getByRole("button", { name: /confirm.*run/i }).first().waitFor({ timeout: 180000 });
  await page.waitForTimeout(3000);
  // Read each captured chat response body, but never block on an SSE stream that
  // stays open: race each text() with a 6s timeout.
  for (const { url, resp } of respObjs) {
    const t = await withTimeout(resp.text().catch(() => null) as Promise<string | null>, 6000);
    if (typeof t === "string") bodies.push({ url, text: t });
    else console.log(`[diag] chat response url=${url} body UNREADABLE (stream open / timed out)`);
  }

  // 1) Viewer's authoritative delivered map (full object)
  const dbg = await page.evaluate(() => {
    const el = document.querySelector("[data-debug-inline-params]");
    return el ? el.getAttribute("data-debug-inline-params") : "(none)";
  });
  console.log("[diag] DATA_DEBUG_INLINE_PARAMS: " + dbg);

  // 2) Parse SSE bodies: collect every JSON object out of `data: {...}` lines + raw JSON bodies
  const objs: any[] = [];
  for (const b of bodies) {
    console.log(`[diag] chat response url=${b.url} bytes=${b.text.length}`);
    // try whole-body JSON
    try { objs.push(JSON.parse(b.text)); } catch {}
    // SSE lines
    for (const line of b.text.split(/\r?\n/)) {
      const m = line.match(/^data:\s*(\{.*\}|\[.*\])\s*$/);
      if (m) { try { objs.push(JSON.parse(m[1])); } catch {} }
    }
  }
  console.log(`[diag] parsed ${objs.length} JSON object(s) from ${bodies.length} chat response(s)`);

  // 3) For each requested path + full s3_uri scan, report on the object(s) that contain a workflow
  const seen = new Set<string>();
  for (const o of objs) {
    const r = o?.response ?? o; // some events wrap under .response
    const probes: [string, any][] = [
      ["response.workflow?.inline_parameters", r?.workflow?.inline_parameters],
      ["response.workflow_ga?.inline_parameters", r?.workflow_ga?.inline_parameters],
      ["response.metadata?.inlineParameters", r?.metadata?.inlineParameters],
      ["response.metadata?.workflow?.inline_parameters", r?.metadata?.workflow?.inline_parameters],
      ["response.inlineParameters", r?.inlineParameters],
    ];
    for (const [label, val] of probes) {
      if (val !== undefined) {
        const key = label + cut(val);
        if (!seen.has(key)) { seen.add(key); console.log(`[diag] PATH ${label} = ${cut(val)}`); }
      }
    }
  }
  // 4) scans across everything
  const scan = (needle: string, tag: string) => {
    const hits = new Set<string>();
    for (const o of objs) for (const h of findPaths(o, needle)) hits.add(h);
    console.log(`[diag] === PATHS CONTAINING '${needle}' (${tag}) ===`);
    for (const h of hits) console.log(`[diag] ${tag} ` + h);
  };
  scan("s3_uri=", "S3URI");
  scan("cryo_inputs.json", "CRYOJSON");

  // 5) dump EVERY inline-params object found at any depth, with its path
  console.log("[diag] === ALL inline_parameters / inlineParameters OBJECTS (any depth) ===");
  const dumpInline = (obj: any, base = "$") => {
    if (!obj || typeof obj !== "object") return;
    for (const k of Object.keys(obj)) {
      if ((k === "inline_parameters" || k === "inlineParameters") && obj[k] && typeof obj[k] === "object") {
        console.log(`[diag] INLINEOBJ ${base}.${k} = ${cut(obj[k], 600)}`);
      }
      dumpInline(obj[k], `${base}.${k}`);
    }
  };
  for (const o of objs) dumpInline(o);

  // 6) RAW occurrences of "dataset_id" in the SSE text (bypasses JSON-parse gaps)
  console.log("[diag] === RAW 'dataset_id' OCCURRENCES IN SSE TEXT ===");
  for (const b of bodies) {
    let idx = 0; let n = 0;
    while ((idx = b.text.indexOf("dataset_id", idx)) !== -1 && n < 12) {
      console.log(`[diag] RAWHIT @${idx}: …${b.text.slice(Math.max(0, idx - 30), idx + 140).replace(/\s+/g, " ")}…`);
      idx += 10; n++;
    }
  }
  // 7) EVT with .workflow: dump its workflow subtree keys + required_params + inline_parameters
  console.log("[diag] === EVT.workflow SUBTREE ===");
  for (const o of objs) {
    const r = o?.response ?? o;
    const w = r?.workflow;
    if (w && typeof w === "object") {
      console.log("[diag] WF keys=" + Object.keys(w).join(","));
      console.log("[diag] WF.inline_parameters=" + cut(w.inline_parameters, 500));
      console.log("[diag] WF.required_params=" + cut(w.required_params, 700));
      console.log("[diag] WF.workflow_ga?.inline_parameters=" + cut(w.workflow_ga?.inline_parameters, 400));
      console.log("[diag] WF.workflow_ga?.required_params=" + cut(w.workflow_ga?.required_params, 700));
    }
  }
  console.log("[diag] === END ===");
  expect(true).toBe(true);
});
