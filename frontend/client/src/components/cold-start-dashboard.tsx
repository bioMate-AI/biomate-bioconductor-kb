/**
 * ColdStartDashboard — the cold-start function-module dashboard + intent router
 * (data-centric spec 00 §0.4 "the function-module dashboard" and §0.5 "the
 * intent router").
 *
 * Shown when a fresh chat session has no messages yet, where the old
 * hardcoded suggested-query grid used to live (ReturningUserWelcome, which now
 * returns null). It answers the cold-start question — "what can I do here?" —
 * WITHOUT ever showing a browsable list of our inventory.
 *
 * Honesty contract (spec 00 §0.15.1 — the no-inventory rule):
 *   - It shows FUNCTION CATEGORIES (Search & evidence, Data analysis, Design &
 *     generate, Models) and, under each, a few EXAMPLE INTENTS phrased as
 *     things you might say. That is all.
 *   - It NEVER shows a fabricated workflow/tool count, and never claims a
 *     browsable catalogue. There are no numbers on these cards.
 *   - The intent bar routes a described goal to a LANE and a DOMAIN — it
 *     describes what it heard back to you; it does not return a list of names.
 *
 * The four modules and the router heuristic mirror the reference design at
 * reference/claude_design/data_centroid_design/dataui/data-part3.js
 * (window.MODULES + window.ROUTES) and ColdStart.jsx (ModuleDash / IntentBar).
 * The two-way Instant/Cloud read reuses `laneForText` from lane-preview.tsx so
 * the front door cannot contradict the composer's own lane preview; the
 * DOMAIN read is a light domain-aware pass layered on top (lane-preview only
 * resolves the coarse Instant/Cloud lane, not a domain).
 *
 * Clicking an example intent (or typing into the bar and sending) SEEDS the
 * composer via `onSeed` — it does not send. The user still reviews and sends
 * themselves.
 */

import { useState } from "react";
import { Search, FlaskConical, Dna, Sparkles, ChevronRight, Send } from "lucide-react";
import { laneForText, type LaneKind } from "./lane-preview";

// ── Function modules. Categories + example intents only — no counts, no
//    inventory. Copy adapted from the reference window.MODULES. ──────────────
export interface ColdModule {
  id: string;
  /** Short module key, e.g. "Search & evidence". */
  k: string;
  /** One-line description of what the module is for. */
  t: string;
  icon: "search" | "beaker" | "dna" | "sparkles";
  /** A few example intents — click-to-seed the composer. */
  ex: string[];
}

export const COLD_MODULES: ColdModule[] = [
  {
    id: "search",
    k: "Search & evidence",
    t: "A cited answer over literature, databases and patents",
    icon: "search",
    ex: [
      "What is the evidence linking this target to disease?",
      "Pull every reported structure for this target.",
      "Who holds composition-of-matter claims on this scaffold?",
      "Have we assayed this scaffold before, and what did we conclude?",
    ],
  },
  {
    id: "analysis",
    k: "Data analysis",
    t: "Work on your own data — ad-hoc or a validated workflow",
    icon: "beaker",
    ex: [
      "Summarise this assay table and plot potency against logP.",
      "Screen these SMILES for ADMET liabilities, hERG first.",
      "Differential expression between treated and control, then GO enrichment.",
      "Call variants on these samples and flag the clinically relevant ones.",
    ],
  },
  {
    id: "design",
    k: "Design & generate",
    t: "Propose molecules, then optimise and rank them",
    icon: "dna",
    ex: [
      "Generate candidates for this target with drug-like properties.",
      "Optimise this series for potency without losing solubility.",
      "Predict binding affinity for these candidates against my target.",
      "Rank these candidates for developability and show me the top 20.",
    ],
  },
  {
    id: "models",
    k: "Models",
    t: "Run a pre-trained model, or train one on your data",
    icon: "sparkles",
    ex: [
      "Predict the fold of this sequence and show me where the model is unsure.",
      "Score this locus with the sequence model and mark what stands out.",
      "Train a potency predictor on our in-house assay data.",
      "Screen this library against my target and rank the predicted hits.",
    ],
  },
];

const ICONS = {
  search: Search,
  beaker: FlaskConical,
  dna: Dna,
  sparkles: Sparkles,
} as const;

// ── Domain read. lane-preview.laneForText resolves the coarse Instant/Cloud
//    lane; this adds a domain label, mirroring the ordering of the reference
//    window.ROUTES (evidence intents first so a topic keyword inside a "what
//    is known" question is not swallowed by a cloud rule). Categories/domains
//    only — never a list of names, never a count. ───────────────────────────
// Each rule carries the lane its domain lives in (reference window.ROUTES
// pairs every match with a lane). The domain read is the SOURCE OF TRUTH for
// the lane here: e.g. "Molecular design" is a Cloud lane regardless of whether
// the coarse lane-preview verb heuristic caught the specific verb form. When
// no domain rule matches, we fall back to lane-preview's Instant/Cloud read.
const DOMAIN_RULES: Array<{ m: RegExp; dom: string; lane: LaneKind }> = [
  // Evidence first.
  { m: /(patent|freedom.?to.?operate|\bfto\b|composition-of-matter|claims?\b)/i, dom: "Patents", lane: "instant" },
  { m: /(have we|did we|do we (have|know)|our (last|previous|in-house)|what did we conclude)/i, dom: "Internal record", lane: "instant" },
  { m: /(pull every|reported (structure|activit)|registr(y|ies)|curated database)/i, dom: "Databases", lane: "instant" },
  { m: /(evidence|literature|\bsar\b|known (off-?target|sar)|why do|mechanism|cite|trials?\b|endpoints)/i, dom: "Literature", lane: "instant" },
  // Model-side, before topic keywords.
  { m: /(predict the (fold|structure)|model this complex|fold of this|where the model is unsure|\bplddt\b|\bpae\b)/i, dom: "Structure prediction", lane: "cloud" },
  { m: /(score this (locus|sequence|region)|sequence model|per-?base score|what stands out)/i, dom: "Sequence scoring", lane: "cloud" },
  { m: /(screen this library|virtual (library|screen)|predicted hits|re-?rank these hits)/i, dom: "Library screening", lane: "cloud" },
  { m: /(train|fine-?tune|adapt (the |a )?model|re-?train)/i, dom: "Models & training", lane: "cloud" },
  // Design pipeline, most specific first.
  { m: /(optimis|optimiz|multi-?objective|trade-?off|without losing|re-?score|improve.*(while|but|without))/i, dom: "Property optimisation", lane: "cloud" },
  { m: /(generate|de novo|design (a |some )?molecul|scaffold.?hop|enumerat|analogue|grow this fragment)/i, dom: "Molecular design", lane: "cloud" },
  { m: /(affinity|binding|expect to bind|dock|pose|selectiv|predict.*potenc)/i, dom: "Activity prediction", lane: "cloud" },
  // Validated workflows by domain. ADMET before ranking.
  { m: /(herg|admet|smiles|liabilit|toxic|metabolic|solubil)/i, dom: "Drug discovery", lane: "cloud" },
  { m: /(rank|triage|shortlist|developab|prioriti|top \d+|pass every)/i, dom: "Candidate ranking", lane: "cloud" },
  { m: /(proteom|mass spec|protein abundance)/i, dom: "Proteomics", lane: "cloud" },
  { m: /(single-?cell|cell type|composition|doublet)/i, dom: "Transcriptomics", lane: "cloud" },
  { m: /(differential (expression|abundance)|rna-?seq|counts matrix|deseq|enrichment)/i, dom: "Transcriptomics", lane: "cloud" },
  { m: /(variant|wgs|wes|vcf|burden|contaminat|relatedness)/i, dom: "Genomics", lane: "cloud" },
  { m: /(cryo|density map|micrograph)/i, dom: "Structural biology", lane: "cloud" },
  { m: /(cohort|stratif|\bsap\b|primary endpoint)/i, dom: "Clinical", lane: "cloud" },
  { m: /(run-to-run|batch quality|assay batch)/i, dom: "Assay quality", lane: "cloud" },
  // Ad-hoc compute last — the cheap default.
  { m: /(plot|summari|mean|median|correlat|reshape|table|dose.?response|plate|curve)/i, dom: "Data analysis", lane: "instant" },
];

export interface IntentRead {
  lane: LaneKind;
  /** Short lane label from lane-preview (e.g. "Instant · cited answer"). */
  laneLabel: string;
  /** The coarse domain the intent reads as, or null if none matched. */
  domain: string | null;
}

/**
 * Route a described goal to a lane (from lane-preview) + a domain. Returns null
 * for text too short to route meaningfully — the reference gate is >6 chars, so
 * a stray keystroke does not flash a verdict. Never throws.
 */
export function readIntent(text: string | undefined | null): IntentRead | null {
  const t = (text || "").trim();
  if (t.length <= 6) return null;
  const coarse = laneForText(t);
  if (!coarse) return null;
  const dom = DOMAIN_RULES.find((r) => r.m.test(t));
  // The matched domain owns its lane (reference window.ROUTES pairs the two);
  // fall back to the coarse lane-preview read when no domain matched.
  const lane: LaneKind = dom ? dom.lane : coarse.lane;
  // Keep lane-preview's label when it agrees with the resolved lane; otherwise
  // use a plain label matching the resolved lane so chip and dot never disagree.
  const laneLabel =
    coarse.lane === lane
      ? coarse.label
      : lane === "cloud"
        ? "Cloud · validated workflow"
        : "Instant · cited answer";
  return { lane, laneLabel, domain: dom ? dom.dom : null };
}

interface IntentBarProps {
  onSeed: (text: string) => void;
}

function IntentBar({ onSeed }: IntentBarProps) {
  const [q, setQ] = useState("");
  const read = readIntent(q);
  const canSend = q.trim().length > 0;
  return (
    <div data-testid="cold-intent-bar" style={{ display: "flex", flexDirection: "column", gap: 8, width: "100%" }}>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: 8,
          padding: "8px 10px",
          border: "1px solid var(--bm-border, oklch(0.90 0.005 260))",
          borderRadius: 10,
          background: "var(--bm-surface, oklch(0.99 0.002 260))",
        }}
      >
        <Sparkles size={15} aria-hidden style={{ flexShrink: 0, color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }} />
        <input
          data-testid="cold-intent-input"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && q.trim()) onSeed(q.trim());
          }}
          placeholder="Describe the goal — e.g. screen these molecules for hERG, then rank by developability"
          aria-label="Describe the goal"
          style={{
            flex: 1,
            minWidth: 0,
            border: "none",
            outline: "none",
            background: "transparent",
            fontSize: 13,
            color: "var(--bm-text, oklch(0.22 0.01 260))",
          }}
        />
        <button
          type="button"
          data-testid="cold-intent-send"
          disabled={!canSend}
          onClick={() => canSend && onSeed(q.trim())}
          aria-label="Seed the composer with this goal"
          style={{
            display: "inline-flex",
            alignItems: "center",
            justifyContent: "center",
            width: 28,
            height: 28,
            borderRadius: 8,
            border: "none",
            cursor: canSend ? "pointer" : "default",
            opacity: canSend ? 1 : 0.4,
            background: "var(--bm-primary, oklch(0.55 0.20 265))",
            color: "white",
            flexShrink: 0,
          }}
        >
          <Send size={13} />
        </button>
      </div>
      {read && (
        <div
          data-testid="cold-intent-route"
          data-lane={read.lane}
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            flexWrap: "wrap",
            rowGap: 4,
            padding: "6px 10px",
            border: "1px solid var(--bm-border, oklch(0.90 0.005 260))",
            borderRadius: 8,
            fontSize: 12,
            color: "var(--bm-text-dim, oklch(0.62 0.010 260))",
          }}
        >
          <span
            aria-hidden
            style={{
              width: 7,
              height: 7,
              borderRadius: 999,
              flexShrink: 0,
              background:
                read.lane === "cloud"
                  ? "var(--bm-primary, oklch(0.55 0.20 265))"
                  : "var(--bm-ok, oklch(0.62 0.14 155))",
            }}
          />
          <span data-testid="cold-intent-route-lane" style={{ fontWeight: 600, color: "var(--bm-text, oklch(0.22 0.01 260))" }}>
            {read.laneLabel}
          </span>
          {read.domain && (
            <span
              data-testid="cold-intent-route-domain"
              style={{
                padding: "1px 8px",
                borderRadius: 999,
                background: "var(--bm-chip, oklch(0.95 0.01 260))",
                color: "var(--bm-text, oklch(0.22 0.01 260))",
                fontWeight: 500,
              }}
            >
              {read.domain}
            </span>
          )}
        </div>
      )}
    </div>
  );
}

interface ModuleCardProps {
  m: ColdModule;
  onSeed: (text: string) => void;
}

function ModuleCard({ m, onSeed }: ModuleCardProps) {
  const Icon = ICONS[m.icon];
  return (
    <div
      data-testid={`cold-module-${m.id}`}
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 10,
        padding: 16,
        border: "1px solid var(--bm-border, oklch(0.90 0.005 260))",
        borderRadius: 12,
        background: "var(--bm-surface, oklch(0.99 0.002 260))",
        textAlign: "left",
      }}
    >
      <div style={{ display: "flex", alignItems: "flex-start", gap: 10 }}>
        <span
          aria-hidden
          style={{
            display: "inline-flex",
            alignItems: "center",
            justifyContent: "center",
            width: 30,
            height: 30,
            borderRadius: 8,
            background: "var(--bm-chip, oklch(0.95 0.01 260))",
            color: "var(--bm-primary, oklch(0.55 0.20 265))",
            flexShrink: 0,
          }}
        >
          <Icon size={16} />
        </span>
        <div style={{ display: "flex", flexDirection: "column", gap: 2, minWidth: 0 }}>
          <span style={{ fontWeight: 600, fontSize: 13.5, color: "var(--bm-text, oklch(0.22 0.01 260))" }}>{m.k}</span>
          <span style={{ fontSize: 12, color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }}>{m.t}</span>
        </div>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
        {m.ex.map((x) => (
          <button
            key={x}
            type="button"
            data-testid="cold-example"
            onClick={() => onSeed(x)}
            style={{
              display: "flex",
              alignItems: "center",
              gap: 6,
              padding: "6px 8px",
              border: "none",
              borderRadius: 7,
              background: "transparent",
              cursor: "pointer",
              textAlign: "left",
              fontSize: 12.5,
              color: "var(--bm-text, oklch(0.22 0.01 260))",
            }}
          >
            <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis" }}>“{x}”</span>
            <span style={{ flex: 1 }} />
            <ChevronRight size={12} aria-hidden style={{ flexShrink: 0, color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }} />
          </button>
        ))}
      </div>
    </div>
  );
}

export interface ColdStartDashboardProps {
  /** Seed the composer with a goal / example intent. Does not send. */
  onSeed: (text: string) => void;
}

/**
 * The cold-start dashboard: a centred column with the intent bar on top and the
 * four function-module cards below. Purely presentational; all it does is seed
 * the composer.
 */
export function ColdStartDashboard({ onSeed }: ColdStartDashboardProps) {
  return (
    <div
      data-testid="cold-start-dashboard"
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 20,
        width: "100%",
        maxWidth: 720,
        margin: "0 auto",
        padding: "24px 0 8px",
      }}
    >
      <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
        <span style={{ fontSize: 18, fontWeight: 600, letterSpacing: "-0.02em", color: "var(--bm-text, oklch(0.22 0.01 260))" }}>
          What are you trying to do?
        </span>
        <IntentBar onSeed={onSeed} />
      </div>
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(300px, 1fr))",
          gap: 12,
        }}
      >
        {COLD_MODULES.map((m) => (
          <ModuleCard key={m.id} m={m} onSeed={onSeed} />
        ))}
      </div>
    </div>
  );
}

export default ColdStartDashboard;
