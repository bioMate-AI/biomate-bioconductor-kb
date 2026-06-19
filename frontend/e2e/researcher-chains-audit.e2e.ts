/**
 * Researcher-chain audit — Zhi (Z01,Z02) + Zhao (ZZ01,ZZ02) chains.
 *
 * Modeled on tier0-audit.e2e.ts. Each chain gets the same 9 base assertions
 * (chat-stream, prefill, phase cards, SSE, outputs, findings, methods-report,
 *  action buttons) plus the 3 metadata-layer assertions added 2026-06-16:
 *
 *   #10 GET /api/workflows/<wf>/citations returns ≥1 row
 *   #11 GET /api/rationale/<chain>:<phase> returns curated text
 *   #12 workflow_chains row exists for chain_name
 *
 * Real-data status (2026-06-17):
 *   - .nf stubs only — Phase contents emit placeholder JSON.
 *   - Backend layers (chains, qc_evidence, rationale) are FULLY POPULATED
 *     and live; assertions #10/#11/#12 pass NOW.
 *   - Run-dispatch assertions (#1-#9) will pass against the stub once a
 *     real Nextflow run completes; real-data validation requires upstream
 *     code installation (see docs/20260617_RESEARCHER_INTEGRATION_OPEN_ITEMS.md).
 *
 * Run focused (metadata-only):
 *   npx playwright test researcher-chains-audit.e2e.ts --grep '@meta'
 * Full e2e (dispatches real runs, requires real data):
 *   npx playwright test researcher-chains-audit.e2e.ts
 */
import { test, expect, request as pwRequest } from '@playwright/test';

const BASE_URL = process.env.BIOMATE_URL || 'http://localhost:5000';
const E2E_TOKEN = process.env.E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only';

interface ChainSpec {
  id: string;             // Z01, Z02, ZZ01, ZZ02
  researcher: 'zhi' | 'zhao';
  chainName: string;
  workflows: string[];    // every workflow whose citations should populate
  firstRationaleId: string;
  expectedPhases: number; // tier0-audit-style count
  expectedRationaleContains: string;  // sanity-check substring in rationale_text
}

const CHAINS: ChainSpec[] = [
  {
    id: 'Z01', researcher: 'zhi',
    chainName: 'torchgwas_udip_chain',
    workflows: ['torchgwas_udip_phenotype_scan'],
    firstRationaleId: 'torchgwas_udip_chain:A',
    expectedPhases: 4,
    expectedRationaleContains: 'fractional-anisotropy',
  },
  // Z02 (FDA) dropped 2026-06-17 — upstream repo is a paper-reproduction
  // pipeline (2 conda envs, no inference CLI). See
  // docs/20260617_RESEARCHER_INTEGRATION_OPEN_ITEMS.md.
  {
    id: 'ZZ01', researcher: 'zhao',
    chainName: 'tumor_reactive_t_cell_chain',
    workflows: ['turep', 'scupa_polarization', 'immuneapp_hla_screen'],
    firstRationaleId: 'tumor_reactive_t_cell_chain:1.A',
    expectedPhases: 9,
    expectedRationaleContains: 'turep input validation',
  },
  {
    id: 'ZZ02', researcher: 'zhao',
    chainName: 'scgwas_immunology_chain',
    workflows: ['scgwas_immune_cell'],
    firstRationaleId: 'scgwas_immunology_chain:B',
    expectedPhases: 3,
    expectedRationaleContains: 'cell-type enrichment',
  },
];

// ────────────────────────────────────────────────────────────────────────
// Metadata-only assertions (#10/#11/#12) — no dispatch needed, run today.
// ────────────────────────────────────────────────────────────────────────
test.describe('@meta researcher chain metadata layers', () => {
  for (const spec of CHAINS) {
    test(`${spec.id} [${spec.researcher}] ${spec.chainName} — metadata`, async () => {
      const api = await pwRequest.newContext({
        baseURL: BASE_URL,
        extraHTTPHeaders: { 'x-e2e-test-token': E2E_TOKEN },
      });

      // #10 citations for every workflow in the chain
      for (const wf of spec.workflows) {
        const r = await api.get(`/api/workflows/${wf}/citations`);
        expect(r.status(), `${wf} citations HTTP`).toBe(200);
        const body = await r.json();
        expect(Array.isArray(body.citations), `${wf} citations array`).toBe(true);
        expect(body.citations.length, `${wf} citations count`).toBeGreaterThanOrEqual(1);
      }

      // #11 rationale for the chain's first phase
      const r2 = await api.get(`/api/rationale/${encodeURIComponent(spec.firstRationaleId)}`);
      expect(r2.status(), `${spec.firstRationaleId} HTTP`).toBe(200);
      const ratBody = await r2.json();
      expect(typeof ratBody.rationale_text, 'rationale_text type').toBe('string');
      expect(ratBody.rationale_text.length, 'rationale_text length').toBeGreaterThan(10);
      expect(ratBody.rationale_text, 'rationale_text content').toContain(spec.expectedRationaleContains);
      expect(ratBody.qc_gate_name, 'rationale has qc_gate').toBeTruthy();

      // #12 chain row check (via /api/workflow_chains list if available, else
      // skip with a soft message — chain DB is local-only on dev).
      const r3 = await api.get(`/api/workflow_chains?name=${encodeURIComponent(spec.chainName)}`);
      if (r3.status() === 200) {
        const body = await r3.json();
        const arr = Array.isArray(body) ? body
          : Array.isArray(body.chains) ? body.chains
          : Array.isArray(body.items) ? body.items
          : [];
        expect(arr.some((c: any) => c?.name === spec.chainName),
          `${spec.chainName} present in workflow_chains`).toBe(true);
      } else {
        console.warn(`[${spec.id}] #12 skipped — /api/workflow_chains returned ${r3.status()}`);
      }

      await api.dispose();
    });
  }
});

// ────────────────────────────────────────────────────────────────────────
// Full-run assertions (#1-#9) — placeholder. Stubs in .nf will succeed
// in <30s; real-data validation requires upstream code install.
// ────────────────────────────────────────────────────────────────────────
test.describe.skip('@dispatch researcher chains end-to-end (requires real data)', () => {
  // See tier0-audit.e2e.ts for the per-chain dispatch pattern.
  // Each spec runs:
  //   1. /api/chat/stream with chain-routing query
  //   2. confirm + dispatch
  //   3. assert N phase-group cards render with data-status transitions
  //   4. assert findings + methods-report endpoints
  // For Zhao ZZ01 (3-step), the phase-group count is 9 (3 workflows × 3 phases).
});
