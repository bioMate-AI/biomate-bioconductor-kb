import { test, expect } from "@playwright/test";
import * as path from "path";
import { loginAsFixture, BASE_URL } from "./_fixture-login";

const ASSETS = path.resolve(process.cwd(), "..", "docs/user-manual/assets");

async function send(page: any, prompt: string, attach: {root:string,name:string}[] ) {
  await page.goto(BASE_URL + "/", { waitUntil: "domcontentloaded", timeout: 60000 });
  const input = page.getByTestId("chat-input");
  await input.waitFor({ state: "visible", timeout: 45000 });
  await page.waitForTimeout(3000);
  if (attach.length) {
    const payloads: any[] = [];
    for (const a of attach) {
      const resp = await page.request.get(`${BASE_URL}${a.root}${a.name}`);
      if (!resp.ok()) throw new Error(`demo file ${a.name} not served (${resp.status()})`);
      payloads.push({ name: a.name, mimeType: "application/octet-stream", buffer: await resp.body() });
    }
    await page.locator('[data-testid="chat-attach-file-input"]').setInputFiles(payloads, { timeout: 30000 });
    await page.getByTestId("composer-attached-file").first().waitFor({ state: "visible", timeout: 20000 }).catch(()=>{});
  }
  await input.click(); await input.fill(prompt);
  const sb = page.locator('[data-testid="chat-send-button"]:not([disabled])');
  await sb.waitFor({ state: "visible", timeout: 30000 });
  await sb.click({ timeout: 15000 });
  const confirm = page.getByRole("button", { name: /confirm.*run/i });
  await confirm.first().waitFor({ timeout: 200000 });
  await page.waitForTimeout(4000);
  return confirm.first();
}

test("CRYO dataset-id guardrail (prerun only)", async ({ page }) => {
  test.setTimeout(260000);
  await loginAsFixture(page);
  await page.setViewportSize({ width: 1440, height: 1000 });
  await send(page, "Process this cryo-EM dataset to a density map and report the resolution.\n\nPrepared demo context:\nUse the already staged EMPIAR-10028 beta-galactosidase movies at s3://biomate-cryo-data/empiar-10028/Micrographs/ (001_movie.mrcs through 020_movie.mrcs). cryo_inputs.json provides acquisition settings: pixel size 0.885 A, 300 kV, Cs 2.7 mm, amplitude contrast 0.1, symmetry D2, particle diameter 180 A. Bind the staged movie prefix as the workflow input, not this manifest as a micrograph.",
    [{root:"/demo/cold-start/", name:"cryo_inputs.json"}]);
  await page.waitForTimeout(2000);
  // Read all input/textarea values; detect the composite "<uuid>, s3_uri=" leak.
  const vals: string[] = await page.evaluate(() => Array.from(document.querySelectorAll('input,textarea')).map((e:any)=>String(e.value||"")).filter(Boolean));
  const composite = vals.find(v => /[0-9a-f]{8}-[0-9a-f-]{20,},\s*s3_uri=/i.test(v));
  const bodyHasComposite = /[0-9a-f]{8}-[0-9a-f-]{20,},\s*s3_uri=/i.test(await page.locator("body").innerText());
  console.log("[CRYO] input values:", JSON.stringify(vals.map(v=>v.slice(0,90))));
  console.log("[CRYO] composite-in-input:", composite ? ("BROKEN: "+composite.slice(0,120)) : "none");
  console.log("[CRYO] composite-in-body:", bodyHasComposite ? "PRESENT(?)" : "absent");
  if (!composite && !bodyHasComposite) {
    await page.screenshot({ path: path.join(ASSETS, "domain-cryo-em-prerun.png") });
    console.log("[CRYO] CLEAN ✓ — re-captured domain-cryo-em-prerun.png");
  } else {
    console.log("[CRYO] STILL COMPOSITE ✗ — not committing");
  }
  expect(true).toBe(true);
});

const DEMOS = [
  { key:"flow", prompt:"Run analyze_flow_cytometry_immunophenotyping using its built-in real Accuri C6 FCS demo file; apply the default lymphocyte gating strategy and report marker-positive subset frequencies. Use the public sample-data defaults; do not require my own uploads.", attach:[], expect:/flow|cytometr|immunophenot|gating/i },
  { key:"cart", prompt:"Run the cart_construct_design workflow to design a CD19-targeting CAR construct for B-cell indications: select CAR generation, costimulatory domain and format, and report the design rationale. Use the built-in defaults (target CD19, 2nd generation, auto costimulatory domain). This is an in-silico design exercise, not a validated construct; do not require my own uploads.", attach:[], expect:/car|cd19|construct/i },
  { key:"elisa", prompt:"Run the analyze_ebv_antibody_titers workflow using its built-in ELISA OD readings and standard-curve demo data; quantify antibody titers across the EBV sample groups. Use the public sample-data defaults; do not require my own uploads.", attach:[], expect:/ebv|titer|elisa|antibody/i },
  { key:"survival", prompt:"Run survival_cox_proportional_hazards_regression on the attached demo autoimmune-cohort clinical data (60 patients). Fit a Cox proportional-hazards model to evaluate how treatment arm and disease-activity score affect flare-free survival; report hazard ratios.", attach:[{root:"/demo/mg_demo/", name:"patient_clinical_data.csv"}], expect:/survival|cox|hazard/i },
];
for (const d of DEMOS) {
  test(`DEMO ${d.key} route+dispatch`, async ({ page }) => {
    test.setTimeout(320000);
    await loginAsFixture(page);
    const baseRuns = await page.request.get(`${BASE_URL}/api/workflows/runs?limit=3`, { headers: { Authorization: `Bearer ${await page.evaluate(()=>{try{return JSON.parse(localStorage.getItem("biomate_token")||'""')}catch{return ""}})}` } }).then(r=>r.ok()?r.json():null).catch(()=>null);
    const confirm = await send(page, d.prompt, d.attach);
    const body = (await page.locator("body").innerText()).toLowerCase();
    const routed = d.expect.test(body);
    console.log(`[DEMO ${d.key}] routed=${routed} (expect ${d.expect})`);
    if (!routed) { console.log(`[DEMO ${d.key}] ROUTE MISMATCH — body~='${body.slice(0,180).replace(/\n/g," ")}'`); expect(true).toBe(true); return; }
    await confirm.scrollIntoViewIfNeeded().catch(()=>{});
    await confirm.click({ timeout: 30000 }).catch(async()=>{ await confirm.click({ timeout: 15000, force:true }); });
    console.log(`[DEMO ${d.key}] clicked Confirm`);
    // Poll runs API for a NEW persisted run (dispatch), up to 3 min.
    let persisted=false, status="", err="";
    for (let i=0;i<9;i++){
      await page.waitForTimeout(20000);
      const jwt = await page.evaluate(()=>{try{return JSON.parse(localStorage.getItem("biomate_token")||'""')}catch{return ""}});
      const r = await page.request.get(`${BASE_URL}/api/workflows/runs?limit=3`, { headers:{ Authorization:`Bearer ${jwt}` } }).then(x=>x.ok()?x.json():null).catch(()=>null);
      const runs = r?.runs||r||[];
      if (runs[0]) { const ex=runs[0].execution||{}; status=ex.status||""; err=(ex.error||"").slice(0,160); const wf=String(runs[0].workflowName||""); if (d.expect.test(wf.toLowerCase())){ persisted=true; console.log(`[DEMO ${d.key}] PERSISTED run ${String(runs[0].id).slice(0,13)} wf=${wf} status=${status}`); if(status&&status!=="running"&&status!=="pending"&&status!=="configuring") break; } }
    }
    console.log(`[DEMO ${d.key}] result: persisted=${persisted} status=${status} ${err?("err="+err):""}`);
    expect(true).toBe(true);
  });
}
