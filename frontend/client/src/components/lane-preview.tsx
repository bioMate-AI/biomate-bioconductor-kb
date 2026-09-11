/**
 * LanePreview — the composer's pre-send routing verdict (spec 06 §6.2).
 *
 * As the user types, this shows ONE consequence sentence and an Instant/Cloud
 * dot ABOVE the composer input, so the consequence of sending is visible
 * before the send:
 *
 *   ● Instant · a cited answer in seconds
 *   ● Cloud · a validated workflow (~minutes)
 *
 * It is ADVISORY and HONEST — it never blocks send, and it always says that
 * "BioMate will confirm before running anything cloud." The user can override
 * ("answer it instantly instead" / "run a validated pipeline instead").
 *
 * The heuristic is a lightweight client-side mirror of the reference router in
 * reference/claude_design/data_centroid_design/dataui/data-part3.js
 * (window.ROUTES) and its LANE_COPY in ChatView.jsx, collapsed to the two-way
 * Instant/Cloud distinction the spec asks for at the front door:
 *
 *   - consequence words (run / screen / call / align / optimise / train ...),
 *     a named method (DESeq2, STAR, AlphaFold, GATK, sarek ...), or a scale cue
 *     (N samples, a library, a cohort, "these files") -> Cloud
 *   - a "what is known" question (evidence / literature / patents / "have we")
 *     or an ad-hoc calculation on a file you already have -> Instant
 *
 * This mirrors the router's *ordering* (evidence intents first so a topic
 * keyword inside a question doesn't pull it into a cloud lane) without
 * re-implementing the full domain catalogue: the front door only needs to
 * answer "seconds or minutes?", not "which of 20 domains".
 */

import { useEffect, useRef, useState } from "react";

export type LaneKind = "instant" | "cloud";

export interface LaneVerdict {
  lane: LaneKind;
  /** Short chip label, e.g. "Instant · cited answer". */
  label: string;
  /** The one consequence sentence shown to the user. */
  sentence: string;
  /** A coarse read of the intent, shown as a secondary chip (may be empty). */
  read: string;
}

// --- Instant intents (evidence + ad-hoc compute). Checked FIRST, so a topic
//     keyword inside a "what is known" question does not get swallowed by a
//     cloud rule that merely mentions the topic. ---
const INSTANT_RULES: Array<{ m: RegExp; read: string }> = [
  { m: /\b(patent|freedom.?to.?operate|\bfto\b|composition-of-matter)\b/i, read: "a claim-level patent question" },
  { m: /\b(have we|did we|do we (have|know)|our (last|previous|in-house)|what did we conclude)\b/i, read: "a question about our own record" },
  { m: /\b(what is|what are|whats|is there|are there|evidence|literature|papers?|\bsar\b|known (off-?target|sar)|why (do|does|is)|mechanism|explain|summari[sz]e the|cite|reference|which (assay|trial)s? (are|is)|tell me about|difference between)\b/i, read: "a question about what is known" },
  // Ad-hoc compute on a file you already have -- the cheap default, checked
  // after evidence so "summarise the literature" stays Instant-search not compute.
  { m: /\b(plot|summari[sz]e (this|the) (table|file|data|readout)|mean|median|correlat|reshape|pivot|quick look|value counts|head of|first \d+ rows|convert this (file|csv|tsv))\b/i, read: "a calculation on a file you already have" },
];

// --- Cloud intents (validated workflows, design, models). ---
const CLOUD_RULES: Array<{ m: RegExp; read: string }> = [
  // A named method / tool / pipeline is the strongest cloud signal.
  { m: /\b(deseq2?|edger|limma|star|salmon|hisat2?|bwa|gatk|sarek|nf-?core|clusterprofiler|seurat|scanpy|alphafold|boltz|rosetta|autodock|vina|reinvent|cryosparc|relion|macs2?|bowtie2?|kallisto|fastqc|multiqc)\b/i, read: "a named method or pipeline" },
  // Consequence verbs -- running something that produces an artifact.
  { m: /\b(run|execute|launch|screen|call variants?|align|assemble|quantif|differential (expression|abundance)|enrich(ment)?|dock(ing)?|optimi[sz]e|generate (molecul|candidate|structure)|de novo|scaffold.?hop|predict (the )?(fold|structure|binding|affinity|potenc)|train|fine-?tune|adapt (the |a )?model|simulate|reconstruct|process (this|the) (cryo|dataset|samples?))\b/i, read: "a task that produces a validated result" },
  // Scale / dataset cues -- a batch of inputs implies a pipeline, not a chat answer.
  { m: /\b(\d+\s*(samples?|reads?|compounds?|molecul|candidates?|sequences?|structures?|cells?|plates?)|these (samples?|files?|compounds?|reads?|fastqs?|vcfs?|smiles)|this (library|cohort|dataset|batch|assay batch|counts matrix)|fastq|\.vcf|\.bam|whole.?genome|wgs|wes|rna-?seq|single-?cell|cryo-?em|admet|herg)\b/i, read: "a task over a set of inputs" },
];

const INSTANT_LABEL = "Instant · cited answer";
const CLOUD_LABEL = "Cloud · validated workflow";
const INSTANT_SENTENCE = "a cited answer in seconds";
const CLOUD_SENTENCE = "a validated workflow (~minutes)";

// Plain-language "why this?" reason per lane (spec 06 §6.2). Intentionally free
// of any mechanism, regex, keyword list or confidence percentage — it names the
// consequence in words a scientist reads, not how the router decided.
const WHY_COPY: Record<LaneKind, string> = {
  instant:
    "This reads like a question I can answer directly — from literature, curated databases, or a quick look at data you already have — so I answer it here, with sources, rather than running a pipeline.",
  cloud:
    "This reads like standardised analysis that produces a result you'd want to trust and cite — so it runs as a validated workflow with quality gates and an audit-ready report, rather than an off-the-cuff answer.",
};

/**
 * Client-side lane heuristic. Instant rules are checked first (so evidence
 * questions win over topic keywords), then cloud rules; default is Instant --
 * the honest, cheap default. Never throws; empty input yields no verdict.
 */
export function laneForText(text: string | undefined | null): LaneVerdict | null {
  const t = (text || "").trim();
  if (!t) return null;

  const instant = INSTANT_RULES.find((r) => r.m.test(t));
  if (instant) {
    return { lane: "instant", label: INSTANT_LABEL, sentence: INSTANT_SENTENCE, read: instant.read };
  }
  const cloud = CLOUD_RULES.find((r) => r.m.test(t));
  if (cloud) {
    return { lane: "cloud", label: CLOUD_LABEL, sentence: CLOUD_SENTENCE, read: cloud.read };
  }
  // Default: Instant. The front door never over-promises a cloud run.
  return { lane: "instant", label: INSTANT_LABEL, sentence: INSTANT_SENTENCE, read: "a question I can answer directly" };
}

export interface LanePreviewProps {
  /** Current (debounced) composer text. */
  text: string;
  /**
   * Override affordance. Called with the lane the user is forcing:
   *   - "instant" when a cloud verdict offers "answer it instantly instead"
   *   - "cloud"   when an instant verdict offers "run a validated pipeline instead"
   * Optional -- when absent the override chip is not shown.
   */
  onOverride?: (forceLane: LaneKind) => void;
}

/**
 * Server-side lane arbiter, preferred over the client heuristic when it answers
 * in time. Backs the advisory verdict with the REAL router decision (spec 00
 * §0.3, §2.2) so the lane the composer shows matches how the query will route.
 *
 * Contract: advisory + non-blocking. It NEVER delays send — the caller renders
 * the local heuristic immediately; this hook only *upgrades* the displayed lane
 * once the server responds. On error / timeout / non-ok it returns null and the
 * component falls back to the local heuristic. A short debounce and per-request
 * abort keep it to at most one in-flight call for the stable text.
 */
function useServerLane(text: string | undefined | null): LaneVerdict | null {
  const [verdict, setVerdict] = useState<LaneVerdict | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  useEffect(() => {
    const t = (text || "").trim();
    // Clear any stale verdict as soon as the text changes; the local heuristic
    // shows through until (and unless) the server confirms.
    setVerdict(null);
    abortRef.current?.abort();
    if (!t) return;

    const ac = new AbortController();
    abortRef.current = ac;
    // Debounce so a per-keystroke composer doesn't fan out one call per key.
    const timer = setTimeout(async () => {
      // Hard timeout so a slow arbiter never leaves the strip stuck on stale.
      const to = setTimeout(() => ac.abort(), 2500);
      try {
        const resp = await fetch("/api/route/classify", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ text: t }),
          signal: ac.signal,
        });
        if (!resp.ok) return;
        const data = await resp.json().catch(() => null);
        if (!data || data.success === false || (data.lane !== "instant" && data.lane !== "cloud")) return;
        if (ac.signal.aborted) return;
        const isCloud = data.lane === "cloud";
        setVerdict({
          lane: isCloud ? "cloud" : "instant",
          label: isCloud ? CLOUD_LABEL : INSTANT_LABEL,
          sentence: isCloud ? CLOUD_SENTENCE : INSTANT_SENTENCE,
          read: typeof data.why === "string" && data.why ? data.why : (isCloud ? "a validated workflow request" : "a question I can answer directly"),
        });
      } catch {
        // network error / abort / timeout -> stay on the local heuristic
      } finally {
        clearTimeout(to);
      }
    }, 350);

    return () => {
      clearTimeout(timer);
      ac.abort();
    };
  }, [text]);

  return verdict;
}

/**
 * The advisory verdict strip. Renders nothing for empty input. Purely
 * presentational -- it does not gate send. Shows the local heuristic
 * immediately, then upgrades to the server arbiter's verdict once it answers.
 */
export function LanePreview({ text, onOverride }: LanePreviewProps) {
  const local = laneForText(text);
  const server = useServerLane(text);
  const [whyOpen, setWhyOpen] = useState(false);
  // Prefer the server verdict (real router decision); fall back to local.
  const v = server || local;
  if (!v) return null;
  const isCloud = v.lane === "cloud";
  const dot = isCloud ? "var(--bm-primary, oklch(0.55 0.20 265))" : "var(--bm-ok, oklch(0.62 0.14 155))";
  // The server arbiter's `why` (spec §2.2) often already begins with "reads as …";
  // the render prefixes "reads as " itself, so strip any leading copy to avoid the
  // doubled "reads as reads as …" seen on dev. Also trim a trailing period so the
  // sentence reads cleanly inline.
  const displayRead = (v.read || "")
    .replace(/^\s*reads?\s+as\s+/i, "")
    .replace(/\.\s*$/, "")
    .trim();

  return (
    <div
      data-testid="lane-preview"
      data-lane={v.lane}
      style={{
        display: "flex",
        flexDirection: "column",
        gap: 3,
        padding: "4px 4px 8px",
        fontSize: 12,
        lineHeight: 1.4,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 8, flexWrap: "wrap", rowGap: 4 }}>
        <span
          data-testid="lane-preview-chip"
          style={{ display: "inline-flex", alignItems: "center", gap: 6, fontWeight: 600, color: "var(--bm-text, oklch(0.22 0.01 260))" }}
        >
          <span
            aria-hidden
            style={{ width: 7, height: 7, borderRadius: 999, background: dot, flexShrink: 0 }}
          />
          {v.label}
        </span>
        <span style={{ color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }}>· {v.sentence}</span>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 10, flexWrap: "wrap", rowGap: 4, color: "var(--bm-text-dim, oklch(0.62 0.010 260))" }}>
        <span data-testid="lane-preview-read" style={{ fontStyle: "italic" }}>
          reads as {displayRead}
        </span>
        {onOverride && (
          <button
            type="button"
            data-testid="lane-preview-override"
            onClick={() => onOverride(isCloud ? "instant" : "cloud")}
            style={{
              background: "transparent",
              border: "none",
              padding: 0,
              cursor: "pointer",
              color: "var(--bm-primary, oklch(0.55 0.20 265))",
              fontSize: 12,
              textDecoration: "underline",
              textUnderlineOffset: 2,
            }}
          >
            {isCloud ? "answer it instantly instead" : "run a validated pipeline instead"}
          </button>
        )}
        {/* "why this?" — a plain-language reason toggle (spec 06 §6.2). No
            mechanism, no keyword/regex, no confidence percentage. */}
        <button
          type="button"
          data-testid="lane-preview-why"
          aria-expanded={whyOpen}
          onClick={() => setWhyOpen((o) => !o)}
          style={{
            background: "transparent",
            border: "none",
            padding: 0,
            cursor: "pointer",
            color: "var(--bm-primary, oklch(0.55 0.20 265))",
            fontSize: 12,
            textDecoration: "underline",
            textUnderlineOffset: 2,
          }}
        >
          why this?
        </button>
      </div>
      {whyOpen && (
        <p
          data-testid="lane-preview-why-reason"
          style={{
            margin: 0,
            color: "var(--bm-text-dim, oklch(0.62 0.010 260))",
            fontSize: 11.5,
            lineHeight: 1.45,
            maxWidth: "62ch",
          }}
        >
          {WHY_COPY[v.lane]}
        </p>
      )}
      <span style={{ color: "var(--bm-text-dim, oklch(0.62 0.010 260))", fontSize: 11 }}>
        Advisory -- BioMate will confirm before running anything cloud.
      </span>
    </div>
  );
}
