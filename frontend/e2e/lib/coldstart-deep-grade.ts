/**
 * Pure grading for coldstart-analysis-design-deep evidence.
 * Kept free of Playwright so vitest can lock the committee rules.
 */

export type LaunchInfo = { clicked: boolean; reason: string };
export type TerminalInfo = { status: string; error?: string; timedOut?: boolean };
export type AfterInfo = {
  afterShell?: boolean;
  outputsOk?: boolean;
  findingsOk?: boolean;
  paramsOk?: boolean;
  stuckInProgress?: boolean;
  diagnosisOnly?: boolean;
  failSnippet?: string;
};

export type Grade =
  | "BLOCKED_REQUIRED"
  | "NO_LAUNCH"
  | "DISHONEST_FAIL"
  | "HONEST_FAIL"
  | "REAL_PASS"
  | "FAKE_OR_SOFT_PASS";

export function gradeColdstartDeep(args: {
  launch: LaunchInfo;
  terminal: TerminalInfo;
  after: AfterInfo | null;
  useCasePass: boolean;
}): Grade {
  const { launch, terminal, after, useCasePass } = args;
  if (!launch.clicked && launch.reason === "confirm_blocked_required") return "BLOCKED_REQUIRED";
  if (!launch.clicked) return "NO_LAUNCH";

  const failed = /fail|error/i.test(terminal.status);
  if (failed) {
    // Dishonest = spinner / "Analysis in progress" on a failed run.
    // diagnosisOnly alone is NOT dishonest — Outputs often shows RUN FAILED
    // while Findings/Parameters tabs are simply not rendered.
    const snippet = (terminal.error || after?.failSnippet || "").trim();
    const honestFailStrip = /RUN FAILED|Process \w[\w:/\- ]{0,80} failed:|ERROR:/i.test(snippet);
    if (after?.stuckInProgress) return "DISHONEST_FAIL";
    if (honestFailStrip) return "HONEST_FAIL";
    if (after?.diagnosisOnly && !snippet) return "DISHONEST_FAIL";
    return "HONEST_FAIL";
  }

  // Confirm clicked but no run ever started (missing required / silent no-op /
  // runId plumbing miss) — not a soft "completed" path.
  const noRun =
    /no runId|confirm_noop/i.test(terminal.error || "") ||
    ((terminal.status === "n/a" || terminal.status === "unknown" || !terminal.status) &&
      !!terminal.timedOut);
  if (noRun) return "NO_LAUNCH";

  // QC / sequential pause is a real terminal state — incomplete ≠ fake pass.
  if (/^paused$/i.test(terminal.status)) {
    return useCasePass ? "REAL_PASS" : "HONEST_FAIL";
  }

  return useCasePass ? "REAL_PASS" : "FAKE_OR_SOFT_PASS";
}

/** Failed-run After Run content is OK if shell + fail strip (Findings tab optional). */
export function failedRunContentOk(after: AfterInfo | null): boolean {
  if (!after?.afterShell) return false;
  if (after.findingsOk || after.outputsOk || after.paramsOk) return true;
  return !!after.failSnippet && /RUN FAILED|Process .+ failed:|ERROR:/i.test(after.failSnippet);
}
