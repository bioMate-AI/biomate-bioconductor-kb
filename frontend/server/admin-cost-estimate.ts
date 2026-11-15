/**
 * Honest pre-run cost estimate helpers for admin/ops only.
 *
 * confidence: historical | prior | unavailable
 * Never invent fake USD on transport failure — return unavailable.
 * End-user panel must keep CostEstimateBadge absent (wiring-contracts §5).
 */

export type CostConfidence = "historical" | "prior" | "unavailable";

export type HonestCostEstimate = {
  confidence: CostConfidence;
  basis: string;
  assumptions: string[];
  sample_count?: number | null;
  nextflow_path?: string | null;
  domain?: string | null;
  range: { min_vcpu_hrs: number; max_vcpu_hrs: number };
  usd_range?: { min_usd: number; max_usd: number; label?: string } | null;
  instance_type?: string;
};

export const UNAVAILABLE_ESTIMATE = (reason: string): HonestCostEstimate => ({
  confidence: "unavailable",
  basis: reason,
  assumptions: [
    "No invented defaults — backend unreachable or identity missing",
    "Admin/ops capacity planning only",
  ],
  range: { min_vcpu_hrs: 0, max_vcpu_hrs: 0 },
});

/** Normalize Galaxy/Node payloads into the honesty contract. */
export function normalizeHonestEstimate(raw: any): HonestCostEstimate {
  if (!raw || typeof raw !== "object") {
    return UNAVAILABLE_ESTIMATE("empty estimate payload");
  }
  const confidence = String(raw.confidence || "").toLowerCase();
  if (confidence === "unavailable") {
    return {
      confidence: "unavailable",
      basis: String(raw.basis || "unavailable"),
      assumptions: Array.isArray(raw.assumptions) ? raw.assumptions.map(String) : [],
      nextflow_path: raw.nextflow_path ?? null,
      domain: raw.domain ?? null,
      sample_count: raw.sample_count ?? null,
      range: {
        min_vcpu_hrs: Number(raw.range?.min_vcpu_hrs) || 0,
        max_vcpu_hrs: Number(raw.range?.max_vcpu_hrs) || 0,
      },
    };
  }
  if (raw.range && typeof raw.range === "object") {
    return {
      confidence: (confidence === "historical" || confidence === "prior" ? confidence : "prior") as CostConfidence,
      basis: String(raw.basis || "estimate"),
      assumptions: Array.isArray(raw.assumptions) ? raw.assumptions.map(String) : [],
      nextflow_path: raw.nextflow_path ?? null,
      domain: raw.domain ?? null,
      sample_count: raw.sample_count ?? null,
      instance_type: raw.instance_type,
      range: {
        min_vcpu_hrs: Number(raw.range.min_vcpu_hrs) || 0,
        max_vcpu_hrs: Number(raw.range.max_vcpu_hrs) || 0,
      },
      usd_range: raw.usd_range
        ? {
            min_usd: Number(raw.usd_range.min_usd) || 0,
            max_usd: Number(raw.usd_range.max_usd) || 0,
            label: raw.usd_range.label,
          }
        : null,
    };
  }
  // Legacy static shape → treat as prior only if we can derive vCPU-hrs; else unavailable
  return UNAVAILABLE_ESTIMATE("legacy estimate shape without honesty fields");
}

export type HistoricalRunRow = {
  id: string;
  workflowName?: string | null;
  status?: string | null;
  nextflowPath?: string | null;
  domain?: string | null;
  vcpuHours?: number | null;
  usd?: number | null;
  durationSeconds?: number | null;
  costEstimateSnapshot?: HonestCostEstimate | null;
};

function median(nums: number[]): number | null {
  if (!nums.length) return null;
  const s = [...nums].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid]! : (s[mid - 1]! + s[mid]!) / 2;
}

/**
 * Build a historical band from completed-run actuals (median ± 25%, clamped).
 * Returns null when fewer than 2 samples — caller falls through to prior.
 */
export function historicalFromRuns(
  runs: HistoricalRunRow[],
  nextflowPath?: string | null,
  domain?: string | null,
): HonestCostEstimate | null {
  const pathL = (nextflowPath || "").toLowerCase();
  const domainL = (domain || "").toLowerCase();
  const matched = runs.filter((r) => {
    if (String(r.status || "").toLowerCase() !== "completed") return false;
    const vh = r.vcpuHours;
    if (vh == null || !(vh >= 0) || Number.isNaN(vh)) return false;
    const rPath = (r.nextflowPath || r.workflowName || "").toLowerCase();
    if (pathL && rPath.includes(pathL.replace(/^nf-core\//, ""))) return true;
    if (domainL && ((r.domain || "").toLowerCase() === domainL || rPath.includes(domainL))) return true;
    if (!pathL && !domainL) return false;
    return false;
  });
  const values = matched.map((r) => Number(r.vcpuHours)).filter((n) => n >= 0);
  if (values.length < 2) return null;
  const med = median(values);
  if (med == null) return null;
  const min_vh = Math.max(0, med * 0.75);
  const max_vh = med * 1.25;
  const usdVals = matched
    .map((r) => r.usd)
    .filter((u): u is number => typeof u === "number" && u >= 0);
  const out: HonestCostEstimate = {
    confidence: "historical",
    basis: `median of ${values.length} completed runs`,
    assumptions: [
      `Matched ${values.length} completed runs for ${nextflowPath || domain || "workflow"}`,
      "Band = median × 0.75–1.25 (not a quote)",
      "Admin/ops capacity planning only",
    ],
    nextflow_path: nextflowPath || null,
    domain: domain || null,
    range: {
      min_vcpu_hrs: Math.round(min_vh * 1000) / 1000,
      max_vcpu_hrs: Math.round(max_vh * 1000) / 1000,
    },
  };
  if (usdVals.length >= 2) {
    const um = median(usdVals)!;
    out.usd_range = {
      min_usd: Math.round(um * 0.75 * 100) / 100,
      max_usd: Math.round(um * 1.25 * 100) / 100,
      label: "rough historical USD band from ledger (not a quote)",
    };
  }
  return out;
}

/** Derive actual vCPU-hrs from a run's metrics / wall-clock when billing fields exist. */
export function actualVcpuHoursFromRun(run: any): number | null {
  const snap = run?.execution?.costActual || run?.metrics?.billing;
  if (snap && typeof snap.vcpu_hours === "number") return snap.vcpu_hours;
  const totalSec = Number(run?.metrics?.runtime?.totalSeconds);
  const vcpus = Number(
    run?.execution?.billing_vcpus ||
      run?.metrics?.resources?.vcpus ||
      run?.execution?.costEstimateSnapshot?.instance_vcpus ||
      0,
  );
  if (totalSec > 0 && vcpus > 0) {
    return Math.round((totalSec / 3600) * vcpus * 1000) / 1000;
  }
  // Fallback: wall clock between started/completed assuming 4 vCPU (labeled weak)
  const start = run?.execution?.startedAt || run?.startedAt;
  const end = run?.execution?.completedAt || run?.completedAt;
  if (start && end) {
    const ms = new Date(end).getTime() - new Date(start).getTime();
    if (ms > 0) return Math.round((ms / 3600000) * 4 * 1000) / 1000;
  }
  return null;
}

export function compareRow(run: any, nextflowPath?: string): {
  runId: string;
  workflowName: string | null;
  status: string | null;
  estimated_vcpu_hrs: number | null;
  actual_vcpu_hrs: number | null;
  delta_pct: number | null;
  estimate_confidence: string | null;
} {
  const snap = run?.execution?.costEstimateSnapshot as HonestCostEstimate | undefined;
  const estMid =
    snap?.range != null
      ? (Number(snap.range.min_vcpu_hrs) + Number(snap.range.max_vcpu_hrs)) / 2
      : null;
  const actual = actualVcpuHoursFromRun(run);
  let delta: number | null = null;
  if (estMid != null && actual != null && estMid > 0) {
    delta = Math.round(((actual - estMid) / estMid) * 1000) / 10;
  }
  return {
    runId: String(run?.id || ""),
    workflowName: run?.workflowName ?? null,
    status: run?.execution?.status ?? run?.status ?? null,
    estimated_vcpu_hrs: estMid != null ? Math.round(estMid * 1000) / 1000 : null,
    actual_vcpu_hrs: actual,
    delta_pct: delta,
    estimate_confidence: snap?.confidence ?? null,
  };
}
