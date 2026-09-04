/**
 * Typed fixtures for the "Gaps" surfaces, ported from the design prototype
 * (reference/claude_design/data_centroid_design/dataui/data-part4.js —
 * CLARIFY, APPROVAL, TRAJ, ROLES, VERIFY_KINDS, SKIPDEP).
 *
 * These are the canonical example inputs used by the component tests. They are
 * example/demo data — the real components take all data via props.
 */

import type { ClarifyQuestion } from "./clarify-card"
import type { ApprovalGateData } from "./approval-gate"
import type { TrajectoryRow } from "./trajectory-view"
import type { RolesData, VerifyKind } from "./roles-verify"
import type { PhaseSkipInfo } from "./skip-dependency"

// ── CLARIFY ────────────────────────────────────────────────────────────────
export const CLARIFY_QUESTIONS: ClarifyQuestion[] = [
  {
    id: "reference_build",
    q: "Which reference build?",
    field: "reference_build",
    target: "param",
    binds: "schema value",
    why: 'Your goal said "human" — this workflow needs a specific build, and the two are not interchangeable downstream.',
    opts: [
      {
        label: "GRCh38 · Ensembl 110",
        val: "GRCh38.p14/ens110",
        note: "your project instruction 1 says GRCh38",
        pick: true,
      },
      { label: "GRCh38 · GENCODE 44", val: "GRCh38.p14/gencode44", note: "same build, different annotation" },
      { label: "GRCh37 · Ensembl 75", val: "GRCh37/ens75", note: "legacy — only for re-analysing old cohorts" },
    ],
  },
  {
    id: "workflow",
    q: "Which analysis, exactly?",
    field: "workflow",
    target: "workflow",
    binds: "workflow id",
    why: "Three validated workflows match your wording. Picking one selects it by id — we do not re-read the sentence.",
    opts: [
      {
        label: "Differential expression (bulk, two conditions)",
        val: "wf.rnaseq.de.v4",
        note: 'matches "treated vs control"',
        pick: true,
      },
      { label: "Differential expression with covariates", val: "wf.rnaseq.de.cov.v2", note: "if batch must be modelled" },
      { label: "Transcript-level differential usage", val: "wf.rnaseq.dtu.v1", note: "a different question" },
    ],
  },
  {
    id: "output_template",
    q: "What should the run produce?",
    field: "output_template",
    target: "param",
    binds: "schema value",
    why: "The report is written to a template, and this project has more than one.",
    opts: [
      {
        label: "Internal target-triage memo",
        val: "tpl.memo.v3",
        note: "this project's default output requirement",
        pick: true,
      },
      { label: "Manuscript figure set", val: "tpl.figset.v2", note: "vector figures to the project figure spec" },
      { label: "Results tables only", val: "tpl.tables.v1", note: "no prose — for feeding another analysis" },
    ],
  },
]

// ── APPROVAL ─────────────────────────────────────────────────────────────────
export const APPROVAL_DATA: ApprovalGateData = {
  what: "Write this run's outputs into the project record",
  why: "Phase D publishes counts.tsv v4 and the run report into the project. Two downstream runs read that file, and this version becomes the one future runs resolve by default.",
  cost: "writes counts.tsv v4 + report · notifies 2 downstream runs · reversible for 24 h",
  measured: [
    { key: "Consumers affected", measured: "2 downstream runs", threshold: "approval required above 1", verdict: "needs approval" },
    { key: "Overwrites the resolved version", measured: "writes v4", threshold: "earlier versions kept, never deleted", verdict: "pass" },
    { key: "Reversible", measured: "yes · 24 h rollback window", threshold: "—", verdict: "pass" },
  ],
  who: "You can approve this — you own this project.",
  policy: "Publishing to the project record requires an owner. Overriding a quality gate requires a reviewer.",
}

// ── TRAJ ─────────────────────────────────────────────────────────────────────
export const TRAJ_ROWS: TrajectoryRow[] = [
  { t: "0.0s", kind: "route", k: "Routing decision", d: "Read the goal as a standardised differential-abundance analysis. Chose the validated lane over ad-hoc compute because the goal named a figure.", meta: "lane: Cloud · workflow" },
  { t: "0.4s", kind: "tool", k: "resolve_project_files", d: "Matched 2 of 2 input slots from this project.", meta: "0.4s · 2 results" },
  { t: "1.1s", kind: "clarify", k: "Asked you: reference build", d: 'Extractor confidence was low on "human". You answered GRCh38 · Ensembl 110.', meta: "bound to reference_build" },
  { t: "1.3s", kind: "tool", k: "select_workflow", d: "Selected by id, not by re-reading the sentence.", meta: "wf.rnaseq.de.v4" },
  { t: "1.6s", kind: "note", k: "Progress update to you", d: '"Inputs resolved and the pipeline is pinned — starting alignment now."', meta: "mid-run narration" },
  { t: "4m 20s", kind: "gate", k: "Quality gate halted phase B", d: "Library-size floor. Surfaced the measurement and the suggested change rather than deciding.", meta: "awaiting you" },
  { t: "5m 02s", kind: "clarify", k: "You chose: apply the suggestion", d: "2 low-depth samples excluded; recorded in the QC audit.", meta: "bound to sample_exclude" },
  { t: "11m 48s", kind: "note", k: "Post-run reply to you", d: '"1,284 genes move at FDR < 0.05, dominated by interferon signalling. Two samples were excluded at the gate and the effect survives their removal."', meta: "substantive, not a sign-off" },
]

// ── ROLES ────────────────────────────────────────────────────────────────────
export const ROLES_DATA: RolesData = {
  you: "Owner",
  project: "Fibrosis target triage",
  caps: [
    { capability: "Run a workflow", needs: "Viewer and above", allowed: true },
    { capability: "Edit a parameter", needs: "Contributor and above", allowed: true },
    { capability: "Register a model", needs: "Owner", allowed: true },
    { capability: "Override a quality gate", needs: "Reviewer or Owner", allowed: true },
    { capability: "Promote a file to the account", needs: "Owner", allowed: true },
    { capability: "Approve a spend above £500", needs: "Billing owner", allowed: false },
  ],
}

// ── VERIFY_KINDS ─────────────────────────────────────────────────────────────
export const VERIFY_KINDS: VerifyKind[] = [
  { kind: "Workflow QC gate", measuredBy: "a measurement on your data", stops: "halts the run", where: "Spec 07" },
  { kind: "Model eval gate", measuredBy: "held-out performance", stops: "blocks registration", where: "Spec 03" },
  { kind: "Safety gate", measuredBy: "a predicted liability", stops: "rejects a proposal", where: "Spec 05" },
  { kind: "Chemistry validity gate", measuredBy: "structural correctness", stops: "drops a generated structure", where: "Spec 05" },
  { kind: "Human approval", measuredBy: "a person", stops: "pauses until answered", where: "Spec 07" },
]

// ── SKIPDEP ──────────────────────────────────────────────────────────────────
export const SKIPDEP_PHASES: PhaseSkipInfo[] = [
  { id: "A", skippable: false, why: "Phase B and C read A's alignments directly. The workflow declares no skip parameter for it.", blocks: ["B", "C"] },
  { id: "B", skippable: true, param: "--skip-qc", why: "Declared skippable. Downstream reads the cached QC verdict from the previous run." },
  { id: "C", skippable: true, param: "--skip-de", why: "Declared skippable, but D has nothing to enrich without it.", warn: ["D"] },
  { id: "D", skippable: true, param: "--skip-enrich", why: "Declared skippable. Nothing downstream depends on it." },
]
