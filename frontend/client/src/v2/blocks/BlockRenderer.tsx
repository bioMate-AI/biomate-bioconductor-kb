// BlockRenderer — walks a composed Block[] and renders each block through an EXISTING
// design-system primitive. See docs/20261023_GENERATIVE_RESPONSE_COMPOSITION_ARCHITECTURE.md.
//
// Discipline this encodes:
//  • It renders CONTENT/STRUCTURE only. It applies NO colors/fonts/spacing of its own —
//    every block gets `data-block-kind` + a `v2-block-<kind>` class hook that the design
//    system styles exactly. Where a block maps to a built primitive (prose→ReactMarkdown,
//    outputRef→StepOutputPreview), that primitive's exact visual is reused as-is.
//  • Blocks whose design primitive does not exist yet (e.g. `callout`) render minimal,
//    unstyled, semantic markup and are flagged via `data-design-primitive="needed"` —
//    POINT IT OUT to design; never improvise the look here.
//  • This component is unwired (not yet imported by chat-message / AfterRunReport); it is
//    the foundation for the flag-gated migration, not a live path.
import ReactMarkdown from "react-markdown";
import { StepOutputPreview } from "@/components/step-output-preview";
import { BLOCK_PRIMITIVE_MAP, type Block } from "./types";

export interface BlockRendererProps {
  blocks: Block[];
  runId: string;
  projectId?: string | null;
}

function Wrap({ kind, children }: { kind: Block["kind"]; children: React.ReactNode }) {
  const needsDesign = BLOCK_PRIMITIVE_MAP[kind] === null;
  return (
    <div
      className={`v2-block v2-block-${kind}`}
      data-block-kind={kind}
      {...(needsDesign ? { "data-design-primitive": "needed" } : {})}
    >
      {children}
    </div>
  );
}

function RenderBlock({
  block,
  runId,
  projectId,
}: {
  block: Block;
  runId: string;
  projectId?: string | null;
}) {
  switch (block.kind) {
    case "prose":
    case "report":
      return (
        <Wrap kind={block.kind}>
          <ReactMarkdown>{block.markdown}</ReactMarkdown>
        </Wrap>
      );

    case "outputRef":
      // The key reuse: the extension resolver renders Table / Figure / Structure / Log.
      return (
        <Wrap kind="outputRef">
          <StepOutputPreview
            runId={runId}
            file={block.file}
            projectId={projectId ?? undefined}
            onClose={() => {}}
          />
        </Wrap>
      );

    case "keyResult":
      return (
        <Wrap kind="keyResult">
          {block.entity && <span data-block-field="entity">{block.entity}</span>}
          <span data-block-field="metric">{block.metric}</span>
          <span data-block-field="value">{block.value}</span>
          {block.interpretation && (
            <span data-block-field="interpretation">{block.interpretation}</span>
          )}
        </Wrap>
      );

    case "table":
      return (
        <Wrap kind="table">
          <table>
            <thead>
              <tr>
                {block.columns.map((c, i) => (
                  <th key={i}>{c}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {block.rows.map((row, ri) => (
                <tr key={ri}>
                  {row.map((cell, ci) => (
                    <td key={ci}>{cell}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </Wrap>
      );

    case "figure":
      // Maps to the FindingsFigure renderers (FigBars/FigComposition/FigQc), which are
      // not yet exported from AfterRunReport. Minimal label for now; exporting + reusing
      // those is a follow-up increment.
      return (
        <Wrap kind="figure">
          <span data-block-field="figure-kind">{block.figureKind}</span>
          <span data-block-field="title">{block.title}</span>
        </Wrap>
      );

    case "callout":
      // No design-system primitive yet → minimal semantic, flagged for design.
      return (
        <Wrap kind="callout">
          <span data-block-field="severity">{block.severity}</span>
          <span data-block-field="title">{block.title}</span>
          {block.body && <span data-block-field="body">{block.body}</span>}
        </Wrap>
      );

    case "citation":
      return (
        <Wrap kind="citation">
          {block.url ? (
            <a href={block.url} target="_blank" rel="noreferrer" data-block-field="title">
              {block.title}
            </a>
          ) : (
            <span data-block-field="title">{block.title}</span>
          )}
          {block.id && <span data-block-field="id">{block.id}</span>}
        </Wrap>
      );

    default: {
      // Exhaustiveness guard: an unknown block kind renders nothing (and is a type error).
      const _never: never = block;
      void _never;
      return null;
    }
  }
}

export function BlockRenderer({ blocks, runId, projectId }: BlockRendererProps) {
  return (
    <div className="v2-blocks" data-testid="v2-blocks">
      {blocks.map((block, i) => (
        <RenderBlock key={i} block={block} runId={runId} projectId={projectId} />
      ))}
    </div>
  );
}
