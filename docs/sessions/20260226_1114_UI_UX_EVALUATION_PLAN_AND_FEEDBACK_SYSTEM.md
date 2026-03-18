# 20260226_1114 Detailed UI/UX Evaluation Plan and Feedback System (BioMate)

## Objective
Establish a thorough, repeatable UX evaluation program where UI behavior is the final quality gate for BioMate.

## Evaluation Principles
- Evaluate end-to-end from user perspective first, implementation details second.
- Measure both success path and failure path quality.
- Require both objective telemetry and subjective user feedback.
- Treat "completion" as: meaningful output is visible, understandable, and downloadable.

---

## Phase Plan (Detailed)

## Phase 0 - Baseline and Gate Definition (Day 1)
- Define UX release gate and thresholds:
  - Task success >= 85%
  - Median time-to-first-successful-run <= target (persona-specific)
  - Critical UX issues = 0
  - Output actionability pass rate (visualize + download) >= 95%
- Lock benchmark scenarios and persona matrix.
- Freeze test environment and dataset fixtures.

Deliverables:
- UX gate checklist
- Scenario list
- Persona test matrix

## Phase 1 - Expert Heuristic Evaluation (Days 2-3)
- 2-3 evaluators independently run all scenarios.
- Score each dimension and annotate severity.
- Consolidate issues and remove duplicates.

Deliverables:
- Heuristic review report
- Consolidated issue backlog with severity tags

## Phase 2 - Moderated User Testing (Days 4-7)
- Recruit 8-12 users:
  - novice computational users
  - intermediate users
  - power users
- Each user runs same core tasks:
  1) ask for workflow
  2) run workflow
  3) inspect outputs
  4) download outputs
  5) recover from one induced failure
- Capture observations, completion, and confusion moments.

Deliverables:
- Session notes
- Task-level quantitative dashboard
- User quotes by issue cluster

## Phase 3 - Instrumented Analytics Validation (Days 5-10, parallel)
- Add client telemetry events and funnel tracking.
- Validate where users drop off or repeat actions.
- Correlate with failure logs and run IDs.

Deliverables:
- Funnel dashboard
- Drop-off map
- Event quality audit

## Phase 4 - Reliability and Stress UX (Days 8-12)
- Run long-duration and unstable conditions:
  - slow backend
  - timeout
  - partial output availability
  - intermittent network
- Validate clarity and recovery quality.

Deliverables:
- Resilience UX report
- Failure mode recommendations

## Phase 5 - Synthesis and Prioritization (Days 13-14)
- Rank issues by user impact x frequency x fix effort.
- Define 2 sprint roadmap:
  - sprint A: critical/high blockers
  - sprint B: trust/clarity refinements

Deliverables:
- Prioritized roadmap
- Updated UX gate for next release

---

## Dimensions and Measurement Framework

## 1) Discoverability
- Can users find primary actions without hints?
- Metrics: first-click success, misclick count.

## 2) Learnability
- Can new users complete first workflow quickly?
- Metrics: time to first successful run, help requests.

## 3) Input/Prerequisite Clarity
- Do users understand what data/params are required?
- Metrics: pre-run correction count, prerequisite-related failures.

## 4) Execution Transparency
- Are progress and state changes understandable?
- Metrics: status comprehension score, repeated refresh/check behavior.

## 5) Error Recovery Quality
- Are failures actionable and recoverable?
- Metrics: retry success rate, recovery time, abandonment after error.

## 6) Result Comprehension
- Can users interpret what was produced?
- Metrics: "I understand result" self-rating, interpretation accuracy task.

## 7) Output Actionability
- Can users view and download outputs reliably?
- Metrics: visualization success rate, download completion rate.

## 8) Consistency and Predictability
- Do similar controls behave similarly?
- Metrics: consistency defect count.

## 9) Trust and Confidence
- Do users believe system state and outcomes?
- Metrics: confidence score post-task, mismatch reports.

## 10) Accessibility and Usability Hygiene
- Keyboard flow, focus order, contrast, labels.
- Metrics: WCAG checks, keyboard-only task completion.

---

## Scoring Model
- 1-5 score for each dimension.
- Weighted score:
  - Execution transparency, error recovery, output actionability, trust weighted higher.
- Severity mapping:
  - Critical: blocks core user outcome
  - High: major friction or frequent failure
  - Medium: confusion but recoverable
  - Low: polish issue

---

## Scenario Set (Minimum)
1. Happy path: prompt -> workflow -> run -> view output -> download output.
2. Missing prerequisite path: trigger clear corrective guidance.
3. Timeout path: show actionable retry and state clarity.
4. Partial-output path: show accurate output state and next action.
5. Recovery path: rerun with corrected settings, verify trust restoration.

---

## Feedback Facilities to Add in UI

## A) Inline Message Feedback
- Add thumbs up/down on assistant responses and workflow cards.
- On downvote: required reason tags:
  - unclear
  - incorrect
  - too slow
  - failed to run
  - output not useful
- Optional free text.

## B) Post-Run Micro Survey (2-3 questions)
- Trigger after terminal run states.
- Questions:
  - "Was the execution status clear?"
  - "Did the outputs match your expectation?"
  - "Was download/visualization easy?"
- Include quick 1-5 rating + optional comment.

## C) Contextual "Report confusion" Action
- Place near workflow status and output panel.
- One-click attach context:
  - run ID
  - workflow ID
  - execution state
  - last known error
  - timestamp

## D) Download Confirmation Feedback
- After download action:
  - "Did you get the expected file(s)?"
  - yes/no + reason if no

## E) Session-End Pulse
- On session close/inactivity:
  - "Did BioMate help you complete your task today?"
  - simple yes/no + optional note.

---

## Feedback Data Model (Minimum)
- feedback_id
- user_id (or anonymous session id)
- session_id
- message_id (nullable)
- workflow_id (nullable)
- run_id (nullable)
- feedback_type (inline, post_run, confusion_report, download_check, session_pulse)
- rating (nullable)
- reason_tags (array)
- comment_text (nullable)
- ui_context (json)
- created_at

---

## Instrumentation Events (Minimum)
- `chat.prompt_submitted`
- `workflow.generated`
- `workflow.run_clicked`
- `workflow.status_changed`
- `workflow.error_shown`
- `output.panel_opened`
- `output.visualization_opened`
- `output.download_clicked`
- `output.download_completed` (if trackable)
- `feedback.submitted`

Each event should include session and run correlation keys.

---

## Operational Cadence
- Weekly UX triage:
  - Review top pain points by severity and frequency.
- Biweekly release gate review:
  - pass/fail against UX thresholds.
- Monthly trend review:
  - confidence, completion, and recovery trends.

---

## Definition of UX Done (Release Gate)
- Core happy-path pass rate >= threshold.
- No critical UX blockers.
- Output visualization + download success >= threshold.
- Failure path has clear, actionable next steps.
- Feedback capture live and analyzable with correlation IDs.

