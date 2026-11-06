// Composition vocabulary — the block catalog the LLM composes against and the
// BlockRenderer walks. See docs/20261023_GENERATIVE_RESPONSE_COMPOSITION_ARCHITECTURE.md.
//
// Division of labor this encodes:
//  • The LLM composes CONTENT + STRUCTURE: an ordered `Block[]` — which blocks, what
//    data, in what order. It never authors visuals.
//  • Each block renders through an EXISTING design-system primitive; color/font/spacing
//    come from that primitive, exactly. The renderer sets no styling.
//  • Every block that shows data carries `source` provenance; the render+validate gate
//    (later increment) drops any block whose source/number can't be resolved to a real
//    run artifact. Composition is free; provenance is not.
//
// This module is intentionally standalone/unwired — it adds the vocabulary without
// touching the live chat-message / AfterRunReport paths.

/** Provenance every data-bearing block carries. Validated against real run outputs. */
export interface BlockSource {
  /** File the value/content was read from (must resolve to a real run artifact). */
  source_file?: string;
  /** Producing step, when known. */
  step?: string;
}

/** A file reference an outputRef block resolves through the existing viewer resolver. */
export interface BlockFileRef {
  name: string;
  path: string;
  extension: string;
}

/** Figure kinds that map to the existing FindingsFigure renderers. */
export type BlockFigureKind = "bars" | "composition" | "qc";

export type Block =
  // Prose (markdown). Numbers linkify to their source. → ReactMarkdown.
  | { kind: "prose"; markdown: string; source?: BlockSource }
  // One per-entity result. → key-result row (entity-aware).
  | {
      kind: "keyResult";
      entity?: string;
      metric: string;
      value: string;
      interpretation?: string;
      source?: BlockSource;
    }
  // A run output file, rendered by the extension resolver. → StepOutputPreview
  // (covers Table / Figure / Structure / Log). The preferred way to show an artifact.
  | { kind: "outputRef"; file: BlockFileRef; source?: BlockSource }
  // An inline table (not a file). → InlineTableViewer.
  | { kind: "table"; columns: string[]; rows: string[][]; source?: BlockSource }
  // An inline figure. → FindingsFigure renderers (FigBars / FigComposition / FigQc).
  | {
      kind: "figure";
      figureKind: BlockFigureKind;
      title: string;
      data: Array<[string, number]>;
      unit?: string;
      kept?: number;
      total?: number;
      source?: BlockSource;
    }
  // A verdict / alert (safe / HALT / boundary). Primitive not yet in the design system.
  | {
      kind: "callout";
      severity: "info" | "safe" | "warn" | "halt";
      title: string;
      body?: string;
      source?: BlockSource;
    }
  // A literature citation. → citation row.
  | { kind: "citation"; title: string; id?: string; url?: string }
  // A document/report (markdown), versioned per Spec 12. → Report/Document viewer.
  | { kind: "report"; markdown: string; versioned?: boolean; source?: BlockSource };

export type BlockKind = Block["kind"];

/**
 * The integration contract: which EXISTING primitive each block renders through.
 * `null` = no design-system primitive exists yet — POINT IT OUT to Claude Design;
 * the renderer must not improvise its visual.
 */
export const BLOCK_PRIMITIVE_MAP: Record<BlockKind, string | null> = {
  prose: "ReactMarkdown (+ addCitationLinks)",
  keyResult: "key-result row (findings-card)",
  outputRef: "StepOutputPreview (resolveViewer by extension)",
  table: "InlineTableViewer (file-content-view)",
  figure: "FindingsFigure (FigBars / FigComposition / FigQc)",
  callout: null, // design primitive needed
  citation: "citation row (findings-card)",
  report: "MethodsTab / Document viewer (Spec 12)",
};

/** A composed response = an ordered list of blocks + optional provenance digest. */
export interface ComposedResponse {
  blocks: Block[];
}
