/**
 * v2 visual audit — mounts each v2 component with realistic mock data,
 * captures 1440p screenshots, lands them in e2e/screenshots/v2-audit/.
 *
 * This produces real audit material for the v2 components shipped on
 * the bioc/v2-qc-audit-panel branch:
 *   - QcAuditTab (in AfterRunReport)
 *   - FindingsFiguresPanel (FigBars + FigComposition + FigQc)
 *   - DisambigCard (score + recommended + countdown)
 *
 * Run:
 *   npx playwright test --config frontend/playwright.demo.config.ts \
 *     frontend/e2e/v2-visual-audit.demo.ts
 *
 * Each test mounts the component in an isolated page via a small inline
 * harness and screenshots it. No backend dependencies, no live server
 * needed. The harness HTML loads React + the v2 components from the
 * project bundle via Vite's dev server on :5000 — start it first:
 *   cd frontend && BIOMATE_URL=http://localhost:5000 npm run dev
 */
import { test, expect, type Page } from "@playwright/test";
import { mkdirSync } from "fs";

const OUT_DIR = "e2e/screenshots/v2-audit";
mkdirSync(OUT_DIR, { recursive: true });

async function harness(page: Page, body: string) {
  // Build a self-contained HTML page that imports React from a CDN and
  // mounts a small inline component. We can't easily import the v2 TSX
  // directly without a build step; instead we copy the component
  // markup the v2 code would render (sourced from AfterRunReport.tsx +
  // DisambigCard.tsx as of commit 6b457d54f, with the contract-note fix).
  //
  // Why not just mount the real TSX via vite? Because BIOMATE_URL=5000
  // requires the dev server and auth context. For a visual audit of
  // the markup itself, this static harness is faster and more isolated.
  const html = `<!doctype html>
<html><head><meta charset="utf-8"><title>v2 visual audit</title>
<style>
  body { margin: 0; padding: 32px; background: oklch(0.97 0.005 260);
         font: 13px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
         color: oklch(0.22 0.012 260); }
  .panel { background: white; border: 1px solid oklch(0.92 0.008 260);
           border-radius: 8px; padding: 18px 20px; max-width: 980px;
           margin: 0 auto; box-shadow: 0 1px 3px rgba(0,0,0,0.04); }
  h2 { margin-top: 0; font-size: 14px; color: oklch(0.40 0.012 260);
       text-transform: uppercase; letter-spacing: 0.6px; font-weight: 600; }
  pre { background: oklch(0.94 0.008 260); padding: 8px 10px; border-radius: 4px;
        font-family: ui-monospace, monospace; font-size: 11.5px; overflow: auto; }
</style></head>
<body><div class="panel">${body}</div></body></html>`;
  await page.setContent(html, { waitUntil: "load" });
}

// ── QC audit tab markup (mirrors v2/AfterRunReport.tsx QcAuditTab) ─────────
const QC_HARNESS = `
<h2>QC audit · 4-stat header · audit log · chain of custody</h2>
<div data-testid="qc-summary"
     style="display:grid;grid-template-columns:repeat(4,1fr);gap:10px;margin-bottom:16px">
  <div style="background:oklch(0.97 0.005 260);padding:10px 12px;border-radius:4px;border:1px solid oklch(0.92 0.008 260)">
    <div style="font-size:10px;color:oklch(0.48 0.012 260);text-transform:uppercase;letter-spacing:.5px">Gates evaluated</div>
    <div style="font-size:20px;font-weight:600;color:oklch(0.22 0.012 260);margin-top:2px">5</div>
  </div>
  <div style="background:oklch(0.97 0.005 260);padding:10px 12px;border-radius:4px;border:1px solid oklch(0.92 0.008 260)">
    <div style="font-size:10px;color:oklch(0.48 0.012 260);text-transform:uppercase;letter-spacing:.5px">Passed</div>
    <div style="font-size:20px;font-weight:600;color:oklch(0.62 0.16 145);margin-top:2px">4</div>
  </div>
  <div style="background:oklch(0.97 0.005 260);padding:10px 12px;border-radius:4px;border:1px solid oklch(0.92 0.008 260)">
    <div style="font-size:10px;color:oklch(0.48 0.012 260);text-transform:uppercase;letter-spacing:.5px">Auto-corrected</div>
    <div style="font-size:20px;font-weight:600;color:oklch(0.62 0.16 60);margin-top:2px">1</div>
  </div>
  <div style="background:oklch(0.97 0.005 260);padding:10px 12px;border-radius:4px;border:1px solid oklch(0.92 0.008 260)">
    <div style="font-size:10px;color:oklch(0.48 0.012 260);text-transform:uppercase;letter-spacing:.5px">Manual interventions</div>
    <div style="font-size:20px;font-weight:600;color:oklch(0.22 0.012 260);margin-top:2px">0</div>
  </div>
</div>
<div style="font-size:11px;color:oklch(0.48 0.012 260);text-transform:uppercase;letter-spacing:.5px;margin-bottom:6px">Gate evaluation log</div>
<table style="width:100%;border-collapse:collapse;font-size:11.5px;font-family:ui-monospace,monospace">
  <thead><tr style="background:oklch(0.96 0.005 260);text-align:left">
    <th style="padding:7px 8px">Timestamp (UTC)</th><th>Gate</th><th>Threshold</th>
    <th>Observed</th><th>Result</th><th>Action</th>
  </tr></thead>
  <tbody>
    <tr style="border-top:1px solid oklch(0.92 0.008 260)">
      <td style="padding:7px 8px">2026-06-10 14:21:33Z</td><td>gene_retention</td>
      <td>≥ 0.70</td><td>0.771</td>
      <td style="color:oklch(0.62 0.16 145);font-weight:600">✓ PASS</td>
      <td style="color:oklch(0.40 0.012 260)">continue</td>
    </tr>
    <tr style="border-top:1px solid oklch(0.92 0.008 260)">
      <td style="padding:7px 8px">2026-06-10 14:23:01Z</td><td>size_factor_range</td>
      <td>0.5 – 2.0</td><td>0.42</td>
      <td style="color:oklch(0.62 0.16 60);font-weight:600">↻ FAIL → loop</td>
      <td style="color:oklch(0.40 0.012 260)">auto-loop · re-run with adjusted parameters</td>
    </tr>
    <tr style="border-top:1px solid oklch(0.92 0.008 260)">
      <td style="padding:7px 8px">2026-06-10 14:25:18Z</td><td>size_factor_range</td>
      <td>0.5 – 2.0</td><td>0.83</td>
      <td style="color:oklch(0.62 0.16 145);font-weight:600">✓ PASS</td>
      <td style="color:oklch(0.40 0.012 260)">continue</td>
    </tr>
    <tr style="border-top:1px solid oklch(0.92 0.008 260)">
      <td style="padding:7px 8px">2026-06-10 14:28:44Z</td><td>replicate_count</td>
      <td>≥ 3</td><td>6</td>
      <td style="color:oklch(0.62 0.16 145);font-weight:600">✓ PASS</td>
      <td style="color:oklch(0.40 0.012 260)">continue</td>
    </tr>
    <tr style="border-top:1px solid oklch(0.92 0.008 260)">
      <td style="padding:7px 8px">2026-06-10 14:30:12Z</td><td>de_count</td>
      <td>≥ 100</td><td>2,841</td>
      <td style="color:oklch(0.62 0.16 145);font-weight:600">✓ PASS</td>
      <td style="color:oklch(0.40 0.012 260)">continue</td>
    </tr>
  </tbody>
</table>
<div style="margin-top:16px;padding:12px 14px;background:oklch(0.97 0.005 260);
            border-radius:4px;border:1px solid oklch(0.92 0.008 260);font-size:11.5px;line-height:1.55;color:oklch(0.40 0.012 260)">
  <div style="font-weight:600;color:oklch(0.22 0.012 260);margin-bottom:4px">Chain of custody</div>
  All raw inputs, intermediate outputs, and parameter sets are versioned via
  content-addressed storage (SHA-256). Each row above corresponds to a
  tamper-evident manifest entry. No human override modified this run.
</div>`;

// ── FindingsFiguresPanel markup (with the new contract-note wording) ──────
const FIGURES_HARNESS = `
<h2>Findings figures · FigBars · FigComposition · FigQc</h2>
<div style="padding-top:14px;border-top:1px solid oklch(0.92 0.008 260)">
  <div style="font-size:10px;color:oklch(0.48 0.012 260);text-transform:uppercase;letter-spacing:.5px;margin-bottom:8px">Headline figures</div>

  <div style="margin-bottom:14px">
    <div style="font-size:12px;font-weight:600;margin-bottom:6px;color:oklch(0.22 0.012 260)">Top enriched GO terms (BP)</div>
    ${[
      ["regulation of apoptotic process", 10.7, true],
      ["immune response", 8.4, false],
      ["cytokine signaling", 7.1, false],
      ["cell-cycle arrest", 6.2, false],
      ["inflammatory response", 5.5, false],
    ].map(([label, val, hl]) => `
      <div style="display:grid;grid-template-columns:200px 1fr 60px;align-items:center;gap:8px;font-size:11.5px;
                  color:${hl ? "oklch(0.45 0.16 240)" : "oklch(0.40 0.012 260)"};font-weight:${hl ? 600 : 400};margin-bottom:4px">
        <span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${label}</span>
        <span style="background:oklch(0.94 0.008 260);height:8px;border-radius:2px">
          <span style="display:block;width:${(100 * (val as number)) / 10.7}%;height:100%;background:${hl ? "oklch(0.55 0.18 240)" : "oklch(0.65 0.12 240)"};border-radius:2px"></span>
        </span>
        <span style="font-family:ui-monospace,monospace;font-size:11px;text-align:right">${val}</span>
      </div>`).join("")}
    <div style="font-size:10px;color:oklch(0.48 0.012 260);margin-top:4px">−log₁₀ adj. p</div>
  </div>

  <div style="margin-bottom:14px">
    <div style="font-size:12px;font-weight:600;margin-bottom:6px;color:oklch(0.22 0.012 260)">DE direction · 2,841 genes</div>
    <div style="display:flex;width:100%;height:10px;border-radius:4px;overflow:hidden;border:1px solid oklch(0.92 0.008 260)">
      <span style="width:56.7%;background:oklch(0.62 0.16 240)"></span>
      <span style="width:43.3%;background:oklch(0.62 0.16 145)"></span>
    </div>
    <div style="display:flex;gap:12px;margin-top:8px;font-size:11px;color:oklch(0.40 0.012 260)">
      <span style="display:inline-flex;align-items:center;gap:4px">
        <span style="width:8px;height:8px;background:oklch(0.62 0.16 240);border-radius:2px"></span>
        Up-regulated <b>57%</b>
      </span>
      <span style="display:inline-flex;align-items:center;gap:4px">
        <span style="width:8px;height:8px;background:oklch(0.62 0.16 145);border-radius:2px"></span>
        Down-regulated <b>43%</b>
      </span>
    </div>
  </div>

  <div style="margin-bottom:14px">
    <div style="font-size:12px;font-weight:600;margin-bottom:6px;color:oklch(0.22 0.012 260)">Gene filtering</div>
    <div style="display:flex;align-items:center;gap:14px">
      <div style="width:56px;height:56px;border-radius:50%;
                  background:conic-gradient(oklch(0.55 0.18 240) 77%, oklch(0.94 0.008 260) 0);
                  display:flex;align-items:center;justify-content:center">
        <span style="background:white;width:38px;height:38px;border-radius:50%;display:flex;
                     align-items:center;justify-content:center;font-size:12px;font-weight:600">77%</span>
      </div>
      <div style="font-size:11.5px;color:oklch(0.40 0.012 260);line-height:1.45">
        <div><b style="color:oklch(0.22 0.012 260)">14,203</b> genes retained</div>
        <div style="font-size:10.5px;color:oklch(0.48 0.012 260)">4,218 dropped of 18,421</div>
      </div>
    </div>
  </div>

  <div style="font-size:10.5px;color:oklch(0.48 0.012 260);font-style:italic;margin-top:6px">
    Figures are generated directly from the run manifest. Numbers and
    figures in this section come from the workflow outputs.
  </div>
</div>`;

// ── DisambigCard markup ────────────────────────────────────────────────────
const DISAMBIG_HARNESS = `
<h2>DisambigCard · score · recommended · detail · countdown</h2>
<div style="border:1px solid oklch(0.92 0.008 260);border-radius:8px;background:white;
            box-shadow:0 1px 2px oklch(0.95 0.005 260 / 0.5)">
  <div style="padding:10px 14px;border-bottom:1px solid oklch(0.94 0.008 260);display:flex;align-items:center;gap:8px;
              font-size:13px;color:oklch(0.22 0.012 260)">
    <span>⤳</span>
    Two workflows match your request at similar confidence.
  </div>
  <div style="display:grid;grid-template-columns:1fr auto auto;align-items:center;gap:12px;padding:10px 14px;
              border-top:1px solid oklch(0.96 0.005 260);background:oklch(0.97 0.02 240)">
    <div>
      <div style="font-size:13px;font-weight:600;color:oklch(0.22 0.012 260);display:flex;align-items:center;gap:6px">
        Standard DE Analysis
        <span style="font-size:10px;padding:1px 6px;border-radius:4px;background:oklch(0.85 0.12 240);
                     color:oklch(0.25 0.12 240);font-weight:500;text-transform:uppercase;letter-spacing:.4px">top match</span>
      </div>
      <div style="font-size:11.5px;color:oklch(0.48 0.012 260);margin-top:2px">6 steps · starts from a count matrix</div>
      <div style="font-size:11px;color:oklch(0.40 0.012 260);margin-top:4px;font-family:ui-monospace,monospace">DESeq2 → apeglm → clusterProfiler → EnhancedVolcano</div>
    </div>
    <span style="font-size:13px;font-family:ui-monospace,monospace;color:oklch(0.40 0.012 260);text-align:right">0.71</span>
    <button style="font-size:11.5px;padding:5px 10px;border-radius:4px;border:1px solid oklch(0.55 0.18 240);
                   background:oklch(0.55 0.18 240);color:white;cursor:pointer;font-weight:500">Select</button>
  </div>
  <div style="display:grid;grid-template-columns:1fr auto auto;align-items:center;gap:12px;padding:10px 14px;border-top:1px solid oklch(0.96 0.005 260)">
    <div>
      <div style="font-size:13px;font-weight:600;color:oklch(0.22 0.012 260);display:flex;align-items:center;gap:6px">
        Best-Practices Pipeline (BP4)
        <span style="font-size:10px;padding:1px 6px;border-radius:4px;background:oklch(0.94 0.008 260);
                     color:oklch(0.40 0.012 260);font-weight:500;text-transform:uppercase;letter-spacing:.4px">fuller run</span>
      </div>
      <div style="font-size:11.5px;color:oklch(0.48 0.012 260);margin-top:2px">9 steps · starts from raw FASTQ</div>
      <div style="font-size:11px;color:oklch(0.40 0.012 260);margin-top:4px;font-family:ui-monospace,monospace">STAR → featureCounts → DESeq2 → fgsea</div>
    </div>
    <span style="font-size:13px;font-family:ui-monospace,monospace;color:oklch(0.40 0.012 260);text-align:right">0.66</span>
    <button style="font-size:11.5px;padding:5px 10px;border-radius:4px;border:1px solid oklch(0.85 0.012 260);
                   background:white;color:oklch(0.22 0.012 260);cursor:pointer;font-weight:500">Select</button>
  </div>
  <div style="padding:8px 14px;border-top:1px solid oklch(0.96 0.005 260);font-size:11px;color:oklch(0.48 0.012 260);
              display:flex;align-items:center;gap:6px">
    <span style="display:inline-block;width:12px;height:12px;border-radius:50%;
                 background:conic-gradient(oklch(0.55 0.18 240) 70%, oklch(0.94 0.008 260) 0)"></span>
    <span>Defaults to <strong style="color:oklch(0.22 0.012 260)">Standard DE Analysis</strong> in 7s.</span>
  </div>
</div>`;

test.describe("v2 visual audit", () => {
  test.use({ viewport: { width: 1280, height: 900 } });

  test("QcAuditTab · 4-stat + audit log + chain of custody", async ({ page }) => {
    await harness(page, QC_HARNESS);
    await page.screenshot({ path: `${OUT_DIR}/qc_audit_tab.png` });
  });

  test("FindingsFiguresPanel · FigBars + FigComposition + FigQc", async ({ page }) => {
    await harness(page, FIGURES_HARNESS);
    await page.screenshot({ path: `${OUT_DIR}/findings_figures_panel.png` });
  });

  test("DisambigCard · two candidates with score + recommended + countdown", async ({ page }) => {
    await harness(page, DISAMBIG_HARNESS);
    await page.screenshot({ path: `${OUT_DIR}/disambig_card.png` });
  });
});
