import { type ReactNode } from "react";

/**
 * Shared structured JSON viewer — a legible key/value rendering for JSON values,
 * used by the run-output step previews (step-output-preview.tsx) and the files
 * module dataset preview (datasets/dataset-file-preview.tsx).
 *
 * Scalars render inline (typed + color-coded), arrays as lists / cards, objects
 * as a two-column key→value table (recursive). Much more legible than a raw
 * stringified dump.
 *
 * `renderText` is the fallback used for a top-level scalar and for nesting past
 * the depth guard. Callers can inject a richer text viewer (e.g. the run-output
 * InlineTextViewer with ANSI-strip + tail view); the default is a plain <pre>.
 */
export type RenderTextFn = (text: string) => ReactNode;

const defaultRenderText: RenderTextFn = (text) => (
  <pre className="text-xs font-mono bg-muted/40 p-2 rounded max-h-64 overflow-auto whitespace-pre-wrap break-words">
    {text}
  </pre>
);

export function JsonValueView({
  v,
  depth = 0,
  renderText = defaultRenderText,
}: {
  v: unknown;
  depth?: number;
  renderText?: RenderTextFn;
}) {
  if (v === null || v === undefined) return <span className="text-muted-foreground italic">—</span>;
  if (typeof v === "number" || typeof v === "boolean") {
    return <span className="font-mono text-blue-800 dark:text-blue-300">{String(v)}</span>;
  }
  if (typeof v === "string") {
    // Long / multi-line strings (e.g. a disclaimer block) wrap rather than truncate.
    return <span className="whitespace-pre-wrap break-words">{v}</span>;
  }
  if (Array.isArray(v)) {
    if (v.length === 0) return <span className="text-muted-foreground italic">empty</span>;
    const allScalar = v.every((x) => x === null || typeof x !== "object");
    if (allScalar) {
      return (
        <ul className="list-disc ml-4 space-y-0.5">
          {v.slice(0, 50).map((x, i) => (
            <li key={i}><JsonValueView v={x} depth={depth + 1} renderText={renderText} /></li>
          ))}
          {v.length > 50 && <li className="text-muted-foreground italic">…and {v.length - 50} more</li>}
        </ul>
      );
    }
    return (
      <div className="space-y-1">
        {v.slice(0, 20).map((x, i) => (
          <div key={i} className="rounded border border-border/50 p-1.5">
            <JsonValueView v={x} depth={depth + 1} renderText={renderText} />
          </div>
        ))}
        {v.length > 20 && <div className="text-muted-foreground italic">…and {v.length - 20} more</div>}
      </div>
    );
  }
  if (typeof v === "object") {
    // Guard against pathological nesting — fall back to text past 4 levels.
    if (depth > 4) return <>{renderText(JSON.stringify(v, null, 2))}</>;
    return <JsonObjectTableView obj={v as Record<string, unknown>} depth={depth} renderText={renderText} />;
  }
  return <span>{String(v)}</span>;
}

export function JsonObjectTableView({
  obj,
  depth = 0,
  renderText = defaultRenderText,
}: {
  obj: Record<string, unknown>;
  depth?: number;
  renderText?: RenderTextFn;
}) {
  const entries = Object.entries(obj);
  if (entries.length === 0) return <span className="text-muted-foreground italic">empty</span>;
  return (
    <table className="w-full text-xs border-collapse">
      <tbody>
        {entries.map(([k, val]) => (
          <tr key={k} className="border-b border-border/30 align-top">
            <td className="py-1 pr-3 font-mono text-muted-foreground whitespace-nowrap align-top">{k}</td>
            <td className="py-1 align-top break-words" style={{ wordBreak: "break-word" }}>
              <JsonValueView v={val} depth={depth + 1} renderText={renderText} />
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

/** Structured JSON preview — a key/value view for objects/arrays (legible at a
 *  glance), falling back to `renderText` for a top-level scalar. */
export function InlineJsonView({
  value,
  renderText = defaultRenderText,
  className,
}: {
  value: unknown;
  renderText?: RenderTextFn;
  className?: string;
}) {
  const isObj = value !== null && typeof value === "object";
  return (
    <div data-testid="json-preview" className={className ?? "max-h-64 overflow-auto rounded border bg-muted/20 p-2"}>
      {isObj ? <JsonValueView v={value} renderText={renderText} /> : renderText(String(value))}
    </div>
  );
}
