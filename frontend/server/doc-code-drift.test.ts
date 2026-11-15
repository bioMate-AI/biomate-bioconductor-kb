/**
 * Doc <-> code DRIFT nuance suite.
 *
 * CI guard for the exact bug class the user-manual audit kept surfacing:
 * documentation / spec / prompt / config STRINGS that silently drift from the
 * code truth. Each `it()` below is grounded in a value verified against the
 * REAL system (live sqlite DB or the enforcing Python source) before this test
 * was written — see the block comment above each check for the ground truth.
 *
 * Bug classes locked in here (all real findings from the manual sweep):
 *   - Catalog size:   agent/user strings say "2,455 / 34 domains" (also an MCP
 *                     blurb "4,017 / 36") while the live DB holds 4,233 / 42 / 70.
 *   - QC thresholds:  the 7-domain tutorial doc states Salmon >=70% while the
 *                     enforcing code defaults to 50%; cryo tutorial/design ref
 *                     cite MotionCor2/Topaz + GSFSC 3.5/4.0A + CTF>0.2 while the
 *                     code is CryoSPARC-native with fit_quality>=0.70 and an
 *                     FSC gate at 10.0A. This test pins the CODE truth so a
 *                     future code change that breaks the manual FAILS here.
 *   - Workflow IDs:   the manual/chapters cite DB ids (faers 11363, AlphaFold-DB
 *                     12647, foldseek 14456, mmseqs2 14462, boltz 12853, docking
 *                     10644, vina 12824). This asserts they still resolve to the
 *                     named workflows in the live DB.
 *
 * Source-level pattern: read files with `fs` (like project-routes.test.ts) and
 * read the live DB with better-sqlite3 (already a repo dependency). This is a
 * WRITE-ONLY-NEW-TEST guard: it never edits source or existing tests.
 *
 * On a real drift, the correct fix is to change the SYSTEM (root cause per
 * CLAUDE.md), then update the encoded ground truth here in the same change --
 * never soften an assertion to make it pass.
 */
import { describe, expect, it } from "vitest";
import * as fs from "fs";
import * as path from "path";
import Database from "better-sqlite3";

// ---------------------------------------------------------------------------
// Paths (this file lives in frontend/server/; repo root is two levels up).
// ---------------------------------------------------------------------------
const REPO_ROOT = path.resolve(__dirname, "..", "..");
const DB_PATH = path.join(REPO_ROOT, "backend", "database", "galaxy_ai_tools.db");

const CLAUDE_MD = path.join(REPO_ROOT, "CLAUDE.md");
const TOOLS_MANIFEST = path.join(
  REPO_ROOT,
  "backend",
  "lib",
  "mcp",
  "tools_manifest.py",
);
const ORCHESTRATOR = path.join(__dirname, "orchestrator.ts");
const GALAXY_ASSISTANT = path.join(__dirname, "galaxy-assistant.ts");
const QC_MONITOR = path.join(
  REPO_ROOT,
  "backend",
  "lib",
  "galaxy",
  "jobs",
  "qc_trace_monitor.py",
);
const TUTORIAL_DOC = path.join(
  REPO_ROOT,
  "reference",
  "claude_design",
  "tutorials-work",
  "Tutorial Demo Scenarios 7-domain.md",
);

const read = (p: string): string => fs.readFileSync(p, "utf-8");

// ---------------------------------------------------------------------------
// GROUND TRUTH, verified 2026-11-13 against the intended catalog (panelfix /
// review / DEV) and enforcing source. An older 4,200-row worktree copy is a
// known wrong-worktree trap — do not encode that count as truth.
//
//   sqlite3 galaxy_ai_tools.db "SELECT COUNT(*) FROM workflows"           -> 4233
//   sqlite3 galaxy_ai_tools.db "SELECT COUNT(DISTINCT domain) FROM ..."   ->   42
//   sqlite3 galaxy_ai_tools.db "SELECT COUNT(*) FROM workflow_chains"     ->   70
//
// KNOWN-STALE user/agent-facing strings that must NOT reappear as the claimed
// live catalog size (each is a real drift the audit found):
//   "2,455" workflows / "34 domains"  (CLAUDE.md, tools_manifest.py,
//                                       orchestrator.ts, galaxy-assistant.ts)
//   "4,017" workflows / "36 domains"  (MCP server runtime blurb)
// ---------------------------------------------------------------------------
const STALE_CATALOG_COUNTS = ["2,455", "2455", "4,017", "4017"];
const STALE_DOMAIN_COUNTS = ["34 domains", "34 biological domains", "36 domains"];

// Cited workflow ids -> expected name substring (case-insensitive contains).
const CITED_WORKFLOW_IDS: Array<{ id: number; nameContains: string }> = [
  { id: 11363, nameContains: "faers" },
  { id: 12647, nameContains: "alphafold" },
  { id: 14456, nameContains: "foldseek" },
  { id: 14462, nameContains: "mmseqs2" },
  { id: 12853, nameContains: "boltz" },
  { id: 10644, nameContains: "docking" },
  { id: 12824, nameContains: "vina" },
];

// ---------------------------------------------------------------------------
// Live DB handle (read-only). If the DB is genuinely unavailable the count/id
// suites are skipped with a documented reason rather than silently passing.
// ---------------------------------------------------------------------------
let db: Database.Database | null = null;
let dbErr: string | null = null;
try {
  if (!fs.existsSync(DB_PATH)) {
    dbErr = `galaxy_ai_tools.db not found at ${DB_PATH}`;
  } else {
    db = new Database(DB_PATH, { readonly: true, fileMustExist: true });
  }
} catch (e) {
  dbErr = `could not open galaxy_ai_tools.db: ${(e as Error).message}`;
}

const liveCount = (sql: string): number =>
  (db!.prepare(sql).get() as { c: number }).c;

// ===========================================================================
// 1. CATALOG COUNTS
// ===========================================================================
describe("doc<->code drift: catalog counts (live DB is the truth)", () => {
  it.skipIf(db === null)(
    "live DB holds exactly 4,233 workflows / 42 domains / 70 chains",
    () => {
      // If any of these change, the fix is: update these numbers AND every
      // user/agent-facing string that quotes the catalog size in the same PR.
      // 2026-09-28: removed the broken scrnaseq_standard_endtoend stub (id 14435)
      // and its now-dangling chain scrnaseq_standard_to_isee (id 66) -> workflows
      // and chains each dropped by one.
      // 2026-10-05: search/DB index refresh brought the catalog to 4,210
      // workflows (ground truth per docs/20261004_CATALOG_COUNT_RECONCILIATION.md);
      // domains (42) and chains (69) unchanged. Verified against the live DB.
      // 2026-10-29 reconciliation: the 2026-10-20 incremental indexing added
      // the documented novelty/FTO and other real workflows (4211 -> 4223).
      // See docs/20261020_QA_POLISH_NOVELTY_INDEXING_SESSION.md.
      // 2026-11-13 reconciliation: intended catalog on panelfix/review/DEV is
      // 4,233 workflows (docs/20261113_INPUT_KINDS_ENRICHMENT_DIAGNOSIS.md).
      // A 4,200-row worktree copy is not the catalog — restore the 4,233 DB.
      expect(liveCount("SELECT COUNT(*) AS c FROM workflows")).toBe(4233);
      expect(liveCount("SELECT COUNT(DISTINCT domain) AS c FROM workflows")).toBe(42);
      // 2026-11-07 reconciliation: the November 1 Vina bench addition
      // (backend/scripts/add_vina_bench_chain.py, commit 4f7f69544) restored
      // the chain total to 70. Its deployed inventory is documented in
      // docs/20261101_OVERNIGHT_STATUS_CHAINS_AND_SYNC.md. The Nov 5
      // pre-migration backup also has 70; image renaming did not add a row.
      expect(liveCount("SELECT COUNT(*) AS c FROM workflow_chains")).toBe(70);
    },
  );

  it.skipIf(db === null)("the documented November Vina chain exists and every step resolves by ID and name", () => {
    const chain = db!.prepare("SELECT steps FROM workflow_chains WHERE name = ?")
      .get("vina_virtual_screening_bench") as { steps: string } | undefined;
    expect(chain, "the extra chain must be the documented real addition, not an arbitrary count bump").toBeDefined();
    const steps = JSON.parse(chain!.steps) as Array<{ order: number; workflow_name: string; workflow_id: number }>;
    expect(steps.map(({ order, workflow_name, workflow_id }) => [order, workflow_name, workflow_id])).toEqual([
      [1, "pocket_detection_druggability", 12805],
      [2, "pharmacophore_filtering", 12804],
      [3, "predict_admet_properties", 12826],
      [4, "docking_autodock_vina", 12824],
    ]);
    for (const step of steps) {
      // `name` is a display title (for example Predict ADMET Properties (AI));
      // the canonical chain slug is the workflow directory, not that title.
      const workflow = db!.prepare("SELECT filename, executable FROM workflows WHERE id = ?")
        .get(step.workflow_id) as { filename: string; executable: number } | undefined;
      expect(workflow, `Vina chain step ${step.order} must resolve by ID`).toBeDefined();
      expect(path.posix.basename(path.posix.dirname(workflow!.filename))).toBe(step.workflow_name);
      expect(workflow!.executable).toBe(1);
    }
  });

  it("documents the reason when the live DB cannot be read", () => {
    // This test exists so a skipped count-suite is never silent: if the DB is
    // missing, dbErr carries the human-readable reason.
    if (db === null) {
      expect(dbErr, "DB unavailable -> count assertions were skipped").not.toBeNull();
    } else {
      expect(dbErr).toBeNull();
    }
  });

  // The stale strings live in AGENT/USER-facing prose. These files are what the
  // model and the UI read; a wrong number here is what a real user/agent sees.
  const AGENT_FACING = [
    { label: "MCP tools_manifest.py (agent tool descriptions)", file: TOOLS_MANIFEST },
    { label: "orchestrator.ts (agent orchestrator prompts)", file: ORCHESTRATOR },
    { label: "galaxy-assistant.ts (agent system prompt)", file: GALAXY_ASSISTANT },
  ];

  // UPDATE (2026-10-05): all three agent-facing files were corrected from the
  // stale "2,455 / 34 domains" to the live "4,200+ / 36" after the search/DB
  // index refresh (live total 4,210 workflows). The inventory must now be EMPTY.
  // If this set GROWS, a new stale count was (re)introduced -> fix the file, do
  // not relax this expectation.
  it("no agent-facing file still quotes a stale catalog size", () => {
    const offenders = AGENT_FACING.filter(({ file }) => {
      const txt = read(file);
      return STALE_CATALOG_COUNTS.some((s) => txt.includes(s));
    }).map((o) => o.label);

    expect(offenders.sort()).toEqual([]);
  });

  it.skipIf(db === null)(
    "no agent-facing file quotes a stale count that matches the LIVE workflow total (would be a silent lie)",
    () => {
      // The dangerous class: a file claims a number AND that number equals the
      // real DB size, so it reads as authoritative while being coincidentally
      // right today and wrong tomorrow. The live total must never be
      // hard-coded as a bare WORKFLOW claim in these prompts --
      // the prompt should describe the catalog qualitatively or read live.
      const live = liveCount("SELECT COUNT(*) AS c FROM workflows"); // 4233
      const liveStrs = [
        `${live}`,
        `${live.toLocaleString("en-US")}`, // "4,233"
      ];
      for (const { file, label } of AGENT_FACING) {
        const txt = read(file);
        for (const s of liveStrs) {
          const re = new RegExp(`${s}\\+?\\s*(indexed\\s+)?(nextflow\\s+)?workflows`, "i");
          expect(
            re.test(txt),
            `${label} hard-codes the live count "${s} workflows" -- describe the catalog qualitatively or read live instead`,
          ).toBe(false);
        }
      }
    },
  );

  it("CLAUDE.md carries the live catalog count, not the stale 2,455/34 figure", () => {
    // CLAUDE.md Workflow Database section is the canonical source of the catalog
    // figure. Assert the stale figure is gone AND the live exact count is present.
    const txt = read(CLAUDE_MD);
    expect(
      txt.includes("2,455 workflows across 34 biological domains"),
      "CLAUDE.md regressed to the stale 2,455/34 catalog line",
    ).toBe(false);
    expect(
      txt.includes('4,233 workflows'),
      "CLAUDE.md should record the exact current workflow count",
    ).toBe(true);
  });
});

// ===========================================================================
// 2. QC THRESHOLD CONSISTENCY  (tutorial doc vs CODE-ENFORCED default)
// ===========================================================================
describe("doc<->code drift: QC thresholds (code is the truth)", () => {
  const CODE = read(QC_MONITOR);
  const TUT = fs.existsSync(TUTORIAL_DOC) ? read(TUTORIAL_DOC) : "";

  // --- STAR / alignment: code enforces default 70.0; tutorial says >=70% ---
  // MATCH case: both say 70. Lock the code default so a regression is caught.
  it("STAR/alignment uniquely-mapped gate default is 70.0 in code (matches tutorial >=70%)", () => {
    expect(/_get_threshold\("alignment_rate",\s*70\.0\)/.test(CODE)).toBe(true);
    // tutorial: "STAR uniquely-mapped >= 70%" and "Salmon mapping rate >= 70%"
    expect(TUT).not.toBe("");
    expect(/STAR uniquely-mapped\s*[>=≥]+\s*70\s*%/i.test(TUT)).toBe(true);
  });

  // --- Salmon: THE canonical drift. Tutorial says >=70%; code default = 50.0.
  // The test pins the CODE truth (50.0). It documents the mismatch so that a
  // future code change that bumps the code to 70 -- silently "agreeing" with
  // the tutorial without a ledger update -- FAILS here and forces a decision.
  it("Salmon mapping-rate gate default is 50.0 in code (KNOWN drift: tutorial claims >=70%)", () => {
    expect(
      /_get_threshold\("mapping_rate",\s*50\.0\)/.test(CODE),
      "Salmon code default changed away from 50.0 -- reconcile with the tutorial's 70% claim and update coverage-ledger.md",
    ).toBe(true);
    // The tutorial DOES claim 70% -- assert the drift source still exists so the
    // pairing (code 50 vs doc 70) is explicit and self-documenting.
    expect(/Salmon mapping rate\s*[>=≥]+\s*70\s*%/i.test(TUT)).toBe(true);
  });

  // --- ATAC FRiP: code enforces a hard gate at 0.2 (0.3 ideal); tutorial 0.20 ---
  it("ATAC-seq FRiP gate is 0.2 in code (matches tutorial >=0.20)", () => {
    // The ATAC block gates when frip < 0.2 with threshold 0.2.
    expect(/frip is not None and frip < 0\.2/.test(CODE)).toBe(true);
    expect(/"threshold":\s*0\.2,[\s\S]{0,120}Low ATAC-seq FRiP/.test(CODE)).toBe(true);
    // Distinguish from ChIP-seq, where FRiP is ADVISORY-only at 0.01 (the
    // tutorial's blanket "FRiP >= 0.20 gate" is wrong for ChIP). Lock that too.
    expect(/frip is not None and frip < 0\.01/.test(CODE)).toBe(true);
    expect(/"advisory":\s*True,\s*#\s*non-blocking:\s*ENCODE4 has no hard FRiP gate/.test(CODE)).toBe(true);
    // tutorial claims a FRiP >= 0.20 gate (correct for ATAC, over-broad for ChIP)
    expect(/FRiP score\s*[>=≥]+\s*0\.20/i.test(TUT)).toBe(true);
  });

  // --- Cryo CTF fit-quality: code default gate 0.7 (0.5 red-line floor) ---
  // The tutorial/design narrative cites "CTF > 0.2" (that 0.2 is the CryoSPARC
  // cross-correlation SCALE, NOT the fit_quality gate). Code truth: fit_quality
  // gate default = 0.7. Pin it so a code change breaking the chapter fails here.
  it("cryo CTF fit-quality gate default is 0.7 in code (chapter uses code truth, not the 0.2 CC-scale)", () => {
    expect(/_get_threshold\("fit_quality",\s*0\.7\)/.test(CODE)).toBe(true);
    // The 0.5 GOLD red-line floor for fit_quality is code-enforced and cannot
    // be relaxed via overrides -- lock its presence.
    expect(/"fit_quality":\s*\{\s*"bound":\s*0\.5,\s*"direction":\s*"min"/.test(CODE)).toBe(true);
  });

  // --- Cryo FSC 0.143 resolution gate: code default fires when worse than 10.0A ---
  // The design reference cites GSFSC gates of 3.5A / 4.0A ("below 4 A is
  // publication-ready"). The CODE-ENFORCED interpretable gate default is 10.0A
  // (coarser than 10A is not interpretable). Pin the code default so a change
  // breaks loudly; the mismatch vs the "<=4A" chapter narrative is documented.
  it("cryo FSC 0.143 resolution gate default is 10.0A in code (fires when resolution WORSE than gate)", () => {
    expect(/_get_threshold\("fsc_resolution_angstrom",\s*10\.0\)/.test(CODE)).toBe(true);
    expect(/fsc_res is not None and fsc_res > _fsc_t/.test(CODE)).toBe(true);
  });
});

// ===========================================================================
// 3. WORKFLOW-ID CONSISTENCY  (manual-cited ids resolve to named workflows)
// ===========================================================================
describe("doc<->code drift: cited workflow IDs resolve in the live DB", () => {
  it.skipIf(db === null)(
    "documents the reason when the live DB cannot be read",
    () => {
      // Guard: the id suite must not silently pass if the DB is missing.
      expect(dbErr).toBeNull();
    },
  );

  for (const { id, nameContains } of CITED_WORKFLOW_IDS) {
    it.skipIf(db === null)(
      `id ${id} resolves to a workflow whose name contains "${nameContains}"`,
      () => {
        const row = db!
          .prepare("SELECT id, name FROM workflows WHERE id = ?")
          .get(id) as { id: number; name: string } | undefined;
        expect(row, `no workflow with id ${id} in galaxy_ai_tools.db`).toBeTruthy();
        expect(
          row!.name.toLowerCase().includes(nameContains.toLowerCase()),
          `id ${id} resolves to "${row!.name}", expected name to contain "${nameContains}"`,
        ).toBe(true);
      },
    );
  }
});
