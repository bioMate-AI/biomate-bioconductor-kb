# Drug Development UX Comprehensive Test Plan

Date: 2026-03-09  
Scope: BioMate drug development direction (Direction A) with full UX coverage, including weakly wired paths.

## Objective

Validate that a real user can complete end-to-end drug-development tasks in BioMate and recover gracefully when generation/execution cannot proceed.

## Critical UX Abilities to Validate

1. Workflow generation for drug-development use cases across multiple phases.
2. Clear run controls and execution state transparency (Run/Pause/Resume/Restart/Cancel).
3. Prerequisite clarity + recovery path when inputs are missing.
4. Run manager visibility and execution triage context.
5. Output/result actions (view/download) and artifact-readiness cues.
6. Failure collaboration: if workflow generation is unavailable, assistant gives likely reasons, concrete actions, and focused follow-up questions.

## High-Value Drug Development Use Cases

1. Target validation + docking + ADMET + hERG gate workflow request.
2. Sample-data runnable pathway when user has no input files.
3. Phase I PK NCA workflow request and execution panel readiness.
4. Failure mode forcing diagnostic collaboration path.

## Weakly Wired / Regression-Sensitive Areas

1. Workflow generation failure branch in chat rendering.
2. Prereq recovery button routing from workflow panel to chat.
3. Run manager panel visibility/scope and triage block population.
4. Consistency between backend metadata diagnostics and UI copy.
5. Long-running response behavior and pending/typing cues.

## Automated Coverage (Playwright)

Primary suite: `frontend/e2e/drug-development-ux-comprehensive.e2e.ts`

Test cases:

- DD-001: Generates drug-dev workflow + validates full run control surface.
- DD-002: Validates prerequisite checklist + recovery path.
- DD-003: Validates run manager and execution triage visibility.
- DD-004: Validates collaborative diagnostic UX when generation fails.

Run command:

`cd frontend && BIOMATE_URL=http://localhost:5000 npx playwright test e2e/drug-development-ux-comprehensive.e2e.ts --project chromium`

## Manual Exploratory Add-On (PM Pass)

1. Submit one request per phase cluster:
   - Target identification/validation
   - Hit-to-lead ADMET
   - Preclinical QC
   - Phase I NCA
   - Phase II/III PopPK
2. For each request, verify:
   - explanatory assistant response quality
   - workflow card appears (or failure diagnostics path appears)
   - run/readiness states are understandable
   - user has a concrete next action without guessing
3. Capture screenshot/video evidence at:
   - generation complete
   - prereq blocked
   - recovery prompted
   - run context/triage visible
   - outputs/download action visible

## Exit Criteria

1. Automated suite passes.
2. No silent failures: every blocked path contains explicit reason + user action.
3. At least one run attempt per major phase cluster can be initiated from the UI.
4. Failure-collaboration branch verified with diagnostic payload rendering.
