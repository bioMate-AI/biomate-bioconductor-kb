# Committee review — instruction/universe/routing session (2026-11-10)

Three independent adversarial reviewers audited this session's behavior-changing work
(commits `429ce65239`, `3751a263f4`, `74ac267ffd`, `c9a2ba18f9`, `f0c042f14f`, `000231299f`,
`bfbdff0461`), each on a different lens, reading the real code + running tests rather than trusting
the commit messages. This doc is the consolidated verdict + the fixes applied.

## Overall verdict
**The work is largely solid and honestly described.** Full FE suite **2624 passed / 0 failed**; the
viewer-run gate verified **complete** (no project-scoped run launchable by a viewer via *any* path,
enumerated); corrections project-scoping verified **secure** (parameterized, userId-filtered, not
client-trusted); the input-kind + output-format refactors confirmed genuinely systematic. **But the
committee caught two real issues in my own work** — one a security regression, one an architectural
over-claim — both now fixed.

## Findings + disposition

| # | Finding | Sev | Disposition |
|---|---|---|---|
| 1 | **Invite role-fix introduced a privilege ESCALATION** — the single per-project share token is mutated to the latest invite's role, so a still-pending lower-role link joins at the higher role (invite A viewer, then B editor → A joins editor). | **HIGH** | **FIXED** — reverted the mutation (reuse the single token as-is, no role change). Per-invite tokens is the proper fix but also needs the `/share-link` GET/POST/DELETE endpoints (which operate project-wide) made token-aware — scoped as follow-up, not done. `project-routes.ts:1144`. |
| 2 | **`run_diagnostics` short-circuit is load-bearing, not vestigial** — the research/literature sub-agent (`queryResearch`) never received the universe context, so a run-problem classified `research_question` still reaches the literature path. My commit over-claimed it as a "backstop." | **HIGH/arch** | **FIXED (plumbing + honesty)** — universe context now threaded into `researchPayload.context.user_context` (`galaxy-assistant.ts:5651`); the short-circuit comment corrected to state it is currently load-bearing (`:4869`). Full parity needs the backend research agent to PREFER that context for user-own questions — documented follow-up. |
| 3 | `infer_input_kinds` *replaces* the prose classification wholesale → an auxiliary reference file (`.fa`/`.gtf`/`.sdf`) discards the correct primary `{fastq}` and loses the compatibility boost. | MED | **FIXED** (backend agent) — distinguish primary vs auxiliary kinds; auxiliary/reference files no longer override a prose primary. |
| 4 | 8c gating removed the integration *boost* for *unlabelled* workflows (8a only boosts labelled ones), so an unlabelled MOFA/integration workflow loses its +6 up-rank once a shape is known. | MED | **FIXED** (backend agent) — split 8c: raw-pipeline *penalty* stays gated to "no shape known" (8a owns it when known), integration *boost* still applies for workflows 8a can't handle. |
| 5 | Google-Drive normalized URL loses the filename/extension (`→ "download"`), so Galaxy can't sniff the datatype. | LOW | **Accepted/documented** — cosmetic + user-recoverable (rename the dataset after import; Galaxy may honor Content-Disposition). A filename prompt on the From-URL tab for cloud links is the clean fix if desired. |
| 6 | "Conformance check" is log-only (`console.warn`) telemetry, not validation/enforcement; + minor false pos/neg (counts markdown as words; Chinese `字` cap unit mismatch). | LOW | **Clarified** — it is advisory observability, not a guardrail. Not cited as "deliverables are validated." Improving the parser / surfacing deviations is a follow-up. |
| — | **Scope asymmetry**: runs are user-scoped (all projects), corrections are project-scoped. | note | Deliberate (facts vs preferences); documented here so it isn't read as an oversight. |
| — | Near-tautological test: `correction-standing-context.test.ts` leakage assertions test a mock; the real scoping proof lives in `corrections-project-scope.test.ts`. | note | Acknowledged; scoping is correctly proven elsewhere. |

## Pre-existing, NOT introduced this session (flagged for separate follow-up)
- **SSRF:** `validateRemoteFileUrl` has no private-IP/link-local/metadata blocking (`http://169.254.169.254/…` passes). The Drive normalization does NOT worsen it (protocol/credential checks run after normalization; host is hardcoded). Recommend an IP/allowlist guard.
- **Under-authed personal-compute proxies:** `/api/invocations/:id/ai/autofix` (no ownership check), `autofix3/run` (no auth), `galaxy/workflows/invoke` (optionalAuth) — none attribute a run to a project, so they don't bypass the viewer-run gate, but they're weak-auth surfaces worth hardening.

## Verified solid (reviewers confirmed TRUE)
- Output formats honored in the methods-report + findings deliverables via the one `applyOutputRequirements` chokepoint; no LLM deliverable generator bypasses it.
- Corrections standing + project-scoped (SQL correct, no leak, projectId not client-trusted).
- Runs standing context every turn on the main path (no double-injection).
- Input-kind grounded in attached data on the live default path; data-grounded raw-vs-processed + 8c→fallback is "the cleanest, most genuinely-systematic fix in the batch."
- Viewer-run gate complete; the 2 moderate input-kind issues (#3/#4) are the only real gaps there.

## Net
The committee did its job: it found and we corrected a privilege-escalation regression I introduced
(#1) and an architectural over-claim I made (#2), plus two moderate routing refinements (#3/#4). The
rest of the session's work holds up under adversarial review.
