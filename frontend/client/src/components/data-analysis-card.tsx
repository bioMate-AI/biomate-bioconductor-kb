/**
 * DataAnalysisCard — Track 2D: Inline file analysis card shown in chat after upload.
 *
 * Renders a compact single-line summary (read count, quality, row count, etc.) with an
 * expandable detail section. Appears automatically after a file upload completes.
 */

import { useState } from "react";
import { ChevronDown, ChevronRight, CheckCircle, AlertTriangle, FileText } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";

// ── Types ────────────────────────────────────────────────────────────────────

export interface FileAnalysisResult {
  fileName: string;
  fileType: string;
  analyzed: boolean;
  fileSizeMb?: string;
  note?: string;

  // FASTQ
  readCount?: number | string;
  avgQuality?: string | null;
  avgSeqLen?: number | null;
  passesQualityGate?: boolean;
  qualityGateThreshold?: { minAvgQ?: number; minReads?: number; maxMissingPct?: number };

  // FASTA
  sequenceCount?: number | string;
  avgLength?: number | null;

  // CSV/TSV
  rowCount?: number | string;
  columnCount?: number;
  columns?: string[];
  missingValuesByColumn?: Record<string, number>;

  // VCF
  variantCount?: number | string;
  filterPassCount?: number;
  chromosomeDistribution?: Record<string, number>;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

function fmt(n: number | string | null | undefined): string {
  if (n == null) return "—";
  if (typeof n === "string") return n;
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`;
  return String(n);
}

function buildSummaryLine(r: FileAnalysisResult): string {
  const parts: string[] = [];
  if (r.fileSizeMb) parts.push(`${r.fileSizeMb} MB`);

  if (r.fileType === "fastq" || r.fileType === "fq") {
    if (r.readCount != null) parts.push(`${fmt(r.readCount as number)} reads`);
    if (r.avgQuality != null) parts.push(`avg Q=${r.avgQuality}`);
    if (r.avgSeqLen != null) parts.push(`${r.avgSeqLen} bp`);
  } else if (r.fileType === "fasta" || r.fileType === "fa") {
    if (r.sequenceCount != null) parts.push(`${fmt(r.sequenceCount as number)} seqs`);
    if (r.avgLength != null) parts.push(`avg ${fmt(r.avgLength)} bp`);
  } else if (r.fileType === "csv" || r.fileType === "tsv") {
    if (r.rowCount != null) parts.push(`${fmt(r.rowCount as number)} rows`);
    if (r.columnCount != null) parts.push(`${r.columnCount} cols`);
  } else if (r.fileType === "vcf") {
    if (r.variantCount != null) parts.push(`${fmt(r.variantCount as number)} variants`);
    if (r.filterPassCount != null) parts.push(`${r.filterPassCount} PASS`);
  }

  return parts.join(" · ");
}

// ── Main component ────────────────────────────────────────────────────────────

export function DataAnalysisCard({ result }: { result: FileAnalysisResult }) {
  const [expanded, setExpanded] = useState(false);
  const summaryLine = buildSummaryLine(result);
  const hasQualityGate = result.passesQualityGate !== undefined;
  const passed = result.passesQualityGate;

  return (
    <div
      className={cn(
        "mt-1 rounded-md border text-xs",
        hasQualityGate && !passed
          ? "border-amber-300 bg-amber-50/60 dark:bg-amber-950/20"
          : "border-border bg-muted/30"
      )}
    >
      {/* Summary row */}
      <div
        className="flex items-center gap-2 px-3 py-2 cursor-pointer select-none"
        onClick={() => result.analyzed && setExpanded(e => !e)}
      >
        <FileText className="h-3.5 w-3.5 text-muted-foreground flex-shrink-0" />
        <span className="font-medium truncate max-w-[180px]" title={result.fileName}>
          {result.fileName}
        </span>

        {summaryLine && (
          <span className="text-muted-foreground flex-1 truncate">{summaryLine}</span>
        )}

        {!result.analyzed && result.note && (
          <span className="text-muted-foreground italic">{result.note}</span>
        )}

        {hasQualityGate && (
          <Badge
            variant={passed ? "default" : "secondary"}
            className={cn(
              "ml-auto flex-shrink-0 text-[10px] px-1.5 py-0",
              passed
                ? "bg-green-100 text-green-800 border-green-200"
                : "bg-amber-100 text-amber-800 border-amber-200"
            )}
          >
            {passed ? (
              <><CheckCircle className="h-2.5 w-2.5 mr-0.5" />QC pass</>
            ) : (
              <><AlertTriangle className="h-2.5 w-2.5 mr-0.5" />QC warn</>
            )}
          </Badge>
        )}

        {result.analyzed && (
          <span className="flex-shrink-0 text-muted-foreground ml-1">
            {expanded ? <ChevronDown className="h-3 w-3" /> : <ChevronRight className="h-3 w-3" />}
          </span>
        )}
      </div>

      {/* Expanded details */}
      {expanded && result.analyzed && (
        <div className="px-3 pb-3 pt-0 border-t border-border/50 space-y-2 mt-0.5">

          {/* FASTQ details */}
          {(result.fileType === "fastq" || result.fileType === "fq") && (
            <div className="grid grid-cols-3 gap-2">
              <Stat label="Reads" value={fmt(result.readCount as number)} />
              <Stat label="Avg quality" value={result.avgQuality ? `Q${result.avgQuality}` : "—"} />
              <Stat label="Avg length" value={result.avgSeqLen != null ? `${result.avgSeqLen} bp` : "—"} />
              {result.fileSizeMb && <Stat label="File size" value={`${result.fileSizeMb} MB`} />}
              {result.qualityGateThreshold?.minAvgQ && (
                <Stat label="Min Q threshold" value={`Q${result.qualityGateThreshold.minAvgQ}`} />
              )}
            </div>
          )}

          {/* FASTA details */}
          {(result.fileType === "fasta" || result.fileType === "fa") && (
            <div className="grid grid-cols-3 gap-2">
              <Stat label="Sequences" value={fmt(result.sequenceCount as number)} />
              <Stat label="Avg length" value={result.avgLength != null ? `${fmt(result.avgLength)} bp` : "—"} />
              {result.fileSizeMb && <Stat label="File size" value={`${result.fileSizeMb} MB`} />}
            </div>
          )}

          {/* CSV/TSV details */}
          {(result.fileType === "csv" || result.fileType === "tsv") && (
            <div className="space-y-2">
              <div className="grid grid-cols-3 gap-2">
                <Stat label="Rows" value={fmt(result.rowCount as number)} />
                <Stat label="Columns" value={String(result.columnCount ?? "—")} />
                {result.fileSizeMb && <Stat label="File size" value={`${result.fileSizeMb} MB`} />}
              </div>
              {result.columns && result.columns.length > 0 && (
                <div>
                  <p className="text-[10px] text-muted-foreground mb-1">Columns:</p>
                  <div className="flex flex-wrap gap-1">
                    {result.columns.slice(0, 12).map(col => (
                      <span key={col} className="bg-muted rounded px-1.5 py-0.5 text-[10px]">{col}</span>
                    ))}
                    {result.columns.length > 12 && (
                      <span className="text-muted-foreground text-[10px]">+{result.columns.length - 12} more</span>
                    )}
                  </div>
                </div>
              )}
              {result.missingValuesByColumn && Object.keys(result.missingValuesByColumn).length > 0 && (() => {
                const highMissing = Object.entries(result.missingValuesByColumn)
                  .filter(([, v]) => v > 0)
                  .sort(([, a], [, b]) => b - a)
                  .slice(0, 5);
                if (!highMissing.length) return null;
                const totalRows = typeof result.rowCount === "number" ? result.rowCount : 1;
                return (
                  <div>
                    <p className="text-[10px] text-muted-foreground mb-1">Missing values (top columns):</p>
                    <div className="flex flex-wrap gap-1">
                      {highMissing.map(([col, count]) => (
                        <span key={col} className="bg-amber-50 text-amber-800 rounded px-1.5 py-0.5 text-[10px]">
                          {col}: {((count / totalRows) * 100).toFixed(0)}%
                        </span>
                      ))}
                    </div>
                  </div>
                );
              })()}
            </div>
          )}

          {/* VCF details */}
          {result.fileType === "vcf" && (
            <div className="space-y-2">
              <div className="grid grid-cols-3 gap-2">
                <Stat label="Variants" value={fmt(result.variantCount as number)} />
                <Stat label="FILTER PASS" value={String(result.filterPassCount ?? "—")} />
                {result.fileSizeMb && <Stat label="File size" value={`${result.fileSizeMb} MB`} />}
              </div>
              {result.chromosomeDistribution && Object.keys(result.chromosomeDistribution).length > 0 && (
                <div>
                  <p className="text-[10px] text-muted-foreground mb-1">Chromosomes:</p>
                  <div className="flex flex-wrap gap-1">
                    {Object.entries(result.chromosomeDistribution)
                      .sort(([, a], [, b]) => b - a)
                      .slice(0, 10)
                      .map(([chr, count]) => (
                        <span key={chr} className="bg-muted rounded px-1.5 py-0.5 text-[10px]">
                          {chr}: {count}
                        </span>
                      ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* QC gate message */}
          {hasQualityGate && !passed && result.qualityGateThreshold && (
            <div className="flex items-start gap-1.5 text-amber-700 mt-1">
              <AlertTriangle className="h-3 w-3 flex-shrink-0 mt-0.5" />
              <span className="text-[10px]">
                {result.fileType === "fastq"
                  ? `Average quality Q${result.avgQuality} is below recommended threshold (Q${result.qualityGateThreshold.minAvgQ}). Consider quality trimming before running workflow.`
                  : `Missing value rate exceeds ${result.qualityGateThreshold.maxMissingPct}%. Review columns before workflow execution.`}
              </span>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className="text-[10px] text-muted-foreground">{label}</p>
      <p className="font-medium">{value}</p>
    </div>
  );
}
