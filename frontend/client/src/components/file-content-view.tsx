/**
 * Shared file-content viewers — the format-rendering surface used by BOTH the
 * run-output step previews (step-output-preview.tsx) and the files-module
 * dataset preview (datasets/dataset-file-preview.tsx), so a CSV/TSV, STAR/RELION
 * table, JSON, log or sequence file looks the same wherever it is opened.
 *
 * Pure renderers only (no run-specific sidecar fetches, interactive launchers or
 * domain-specific DL/cryo viewers — those stay in step-output-preview). Depends
 * only on i18n, utils, lucide icons and the structured JSON viewer.
 */
import { useState } from "react";
import { ChevronDown, ChevronUp } from "lucide-react";
import { t } from "@/lib/i18n";
import { cn, stripAnsi } from "@/lib/utils";
import { InlineJsonView } from "./json-value-view";

// Tabular formats routed to the table viewer; everything else renders as text.
const TABLE_EXTS = new Set(["csv", "tsv", "json", "tabular", "star"]);

// ---------------------------------------------------------------------------
// STAR / RELION parser (CryoSPARC / RELION particle tables)
// ---------------------------------------------------------------------------
export function parseStar(text: string): { headers: string[]; rows: string[][] } | null {
  const lines = text.split("\n");
  const headers: string[] = [];
  let inLoop = false;
  let dataStartIdx = -1;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (line === "loop_") { inLoop = true; continue; }
    if (inLoop && line.startsWith("_")) {
      // "_rlnColumnName #N" — take just the column name, strip leading _
      headers.push(line.split(/\s+/)[0].slice(1));
    } else if (inLoop && headers.length > 0 && line && !line.startsWith("#") && !line.startsWith("data_")) {
      dataStartIdx = i;
      break;
    }
  }

  if (headers.length === 0 || dataStartIdx < 0) return null;

  const rows: string[][] = [];
  for (let i = dataStartIdx; i < lines.length && rows.length < 200; i++) {
    const line = lines[i].trim();
    if (!line || line.startsWith("#") || line.startsWith("data_") || line.startsWith("loop_") || line.startsWith("_")) continue;
    rows.push(line.split(/\s+/));
  }

  return rows.length > 0 ? { headers, rows } : null;
}

// Round a full-precision numeric string to ~4 significant figures for display
// (keeps non-numeric and integer-ish values verbatim). Spec 14.2: tables should
// show readable cells, not raw floats like 2.58942740502748.
export function fmtCell(v: string | undefined): string {
  if (v == null || v === "") return "";
  const n = Number(v);
  if (!Number.isFinite(n) || !/^-?\d*\.?\d+(e-?\d+)?$/i.test(v.trim())) return v;
  if (Number.isInteger(n)) return v;
  // Only shorten genuinely long decimals; leave short ones (e.g. 0.05) alone.
  if (v.replace(/^-/, "").length <= 6) return v;
  const abs = Math.abs(n);
  if (abs !== 0 && (abs < 1e-4 || abs >= 1e6)) return n.toExponential(3);
  return String(Number(n.toPrecision(4)));
}

export function TableGrid({ headers, rows, totalRows }: { headers: string[]; rows: string[][]; totalRows: number }) {
  return (
    <div className="rounded border text-xs font-mono">
      {/* Shape header — spec 14.2: the header states N rows × M cols. */}
      <div className="flex items-center justify-between px-2 py-1 border-b bg-muted/60 text-[10px] text-muted-foreground font-sans">
        <span>{t("preview.table_shape", { rows: totalRows.toLocaleString(), cols: headers.length })}</span>
        {totalRows > rows.length && <span>{t("preview.table_showing_first", { n: rows.length.toLocaleString() })}</span>}
      </div>
      <div className="overflow-auto max-h-64">
        <table className="min-w-full">
          <thead className="sticky top-0 bg-muted">
            <tr>
              {headers.map((h, i) => (
                <th key={i} className="px-2 py-1 text-left font-semibold whitespace-nowrap border-b">{h || `Col ${i + 1}`}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, ri) => (
              <tr key={ri} className="hover:bg-muted/40 border-b last:border-0">
                {headers.map((_, ci) => (
                  <td key={ci} className="px-2 py-0.5 max-w-[180px] truncate" title={row[ci]}>{fmtCell(row[ci])}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Text viewer with tail toggle (log files are useful from the end)
// ---------------------------------------------------------------------------
export function InlineTextViewer({ text }: { text: string }) {
  const cleanText = stripAnsi(text);
  const lines = cleanText.split("\n");
  const [showTail, setShowTail] = useState(lines.length > 50);
  const displayed = showTail ? lines.slice(-80).join("\n") : cleanText;
  return (
    <div>
      {lines.length > 50 && (
        <div className="flex items-center justify-between mb-1">
          <span className="text-[10px] text-muted-foreground">{t("preview.lines_total", { n: lines.length })}</span>
          <button
            onClick={() => setShowTail((s) => !s)}
            className="text-[10px] text-primary flex items-center gap-0.5 hover:underline"
          >
            {showTail ? <><ChevronDown className="h-3 w-3" />{t("preview.show_from_start")}</> : <><ChevronUp className="h-3 w-3" />{t("preview.show_tail")}</>}
          </button>
        </div>
      )}
      <pre className={cn("text-xs font-mono bg-muted p-2 rounded max-h-40 overflow-auto whitespace-pre-wrap")}>
        {showTail && lines.length > 80 && <span className="text-muted-foreground italic">… {lines.length - 80} lines above …{"\n"}</span>}
        {displayed}
      </pre>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Inline table viewer (CSV / TSV / JSON / STAR)
// ---------------------------------------------------------------------------
export function InlineTableViewer({ text, ext }: { text: string; ext: string }) {
  const lines = text.trim().split("\n").filter(Boolean);
  if (lines.length === 0) return <p className="text-xs text-muted-foreground">{t("preview.empty_file")}</p>;

  // STAR / RELION format (used by CryoSPARC and RELION for particle tables)
  if (ext === "star" || (text.includes("loop_") && text.includes("_rln"))) {
    const star = parseStar(text);
    if (star) {
      return (
        <>
          <p className="text-[10px] text-muted-foreground mb-1">STAR/RELION format · {star.rows.length} particles shown</p>
          <TableGrid headers={star.headers} rows={star.rows} totalRows={star.rows.length} />
        </>
      );
    }
  }

  const trimmed = text.trim();
  if (ext === "json" || trimmed.startsWith("[") || trimmed.startsWith("{")) {
    let parsed: unknown;
    try { parsed = JSON.parse(trimmed); } catch { parsed = undefined; }
    if (parsed !== undefined) {
      // Only an array of records is tabular; objects and scalars keep their
      // structure — the CSV path below would split them on commas.
      if (Array.isArray(parsed) && parsed.length > 0 && parsed.every((r) => r && typeof r === "object" && !Array.isArray(r))) {
        const records = parsed as Record<string, unknown>[];
        const headers = Object.keys(records[0]);
        const rows = records.slice(0, 200).map((item) =>
          headers.map((h) => (item[h] != null ? (typeof item[h] === "object" ? JSON.stringify(item[h]) : String(item[h])) : ""))
        );
        return <TableGrid headers={headers} rows={rows} totalRows={records.length} />;
      }
      return <InlineJsonView value={parsed} renderText={(txt) => <InlineTextViewer text={txt} />} />;
    }
    if (ext === "json") return <InlineTextViewer text={text} />;
  }

  // Delimiter detection (CSV / TSV)
  const firstLine = lines[0];
  const tabCount = (firstLine.match(/\t/g) || []).length;
  const commaCount = (firstLine.match(/,/g) || []).length;
  const delimiter = tabCount >= commaCount ? "\t" : ",";
  const headers = firstLine.split(delimiter).map((h) => h.trim().replace(/^"|"$/g, ""));
  const rows = lines.slice(1, 201).map((l) => l.split(delimiter).map((c) => c.trim().replace(/^"|"$/g, "")));

  return <TableGrid headers={headers} rows={rows} totalRows={lines.length - 1} />;
}

/**
 * Top-level content router: given a filename + its text content, render the
 * appropriate viewer — tabular formats (CSV/TSV/STAR/tabular) and JSON go to the
 * table/structured viewers; everything else (logs, FASTA, VCF, PDB, YAML, code)
 * renders as text with a tail toggle. Image/PDF are NOT handled here — callers
 * that fetch a signed URL render those directly.
 */
export function FileContentView({ name, text }: { name: string; text: string }) {
  const ext = (name.split(".").pop() || "").toLowerCase();
  if (TABLE_EXTS.has(ext)) return <InlineTableViewer text={text} ext={ext} />;
  return <InlineTextViewer text={text} />;
}
