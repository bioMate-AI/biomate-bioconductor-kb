# BioMate v2: accepted simplification decisions

**Status:** accepted product direction · **Date:** 2026-09-12

This note is the canonical interpretation when an earlier v2 specification or prototype implies a more elaborate flow.

## Keep the four scientific entry points

The dashboard keeps four equal modules:

1. **Search & evidence** — answer an evidence question with sources.
2. **Data analysis** — analyse project data through the appropriate compute path.
3. **Models** — train, adapt, assess, or use a predictive model.
4. **Design & generate** — propose and prioritise candidates.

Each card must express one practical scientific job. Models remain a first-class module; it is not folded into Data analysis.

## Make the normal path small

The default experience is: **state a goal → supply only missing inputs → run → read Summary → inspect Outputs → open the Reproducibility record when needed.**

- BioMate selects the execution lane and explains it. Lane switching is an **Advanced** choice, not a primary decision every user must make.
- The after-run surface has three tabs only: **Summary**, **Outputs**, and **Reproducibility record**.
- The reproducibility record contains expandable Methods, resolved parameters, software, citations, QC/audit decisions, and trajectory. These remain available; they no longer compete as empty top-level tabs.
- Users see simple output names: **Table, Figure, Structure, Report, Log**. A single artifact resolver remains an internal invariant across all surfaces.
- Pareto views, rejection reasons, model calibration detail, and scientific domain viewers remain available on demand, not as required first-view content.

## One file object everywhere

A file is a persistent scientific object, not an upload that disappears into a
chat. The same object identity and version must be usable in Files, chat, run
configuration, outputs, and reports.

- In chat, a user can attach/reference one or more project files from the
  composer (for example, **Compare @result-A.csv with @result-B.csv**). Each
  chip displays a human name and retains the immutable object id/version.
- The assistant must restate the selected inputs before an operation begins and
  validate their roles and compatibility. For a comparison, it checks the
  relevant schema/units/coordinate system and asks a typed mapping question
  only when a safe comparison cannot be inferred.
- A chat operation and an expensive run use the same selected file references;
  no hidden re-upload, implicit “latest” substitution, or second file picker is
  allowed.
- A derived table, figure, claim, or report links back to every source object
  and version. Reopening that link returns to the same Files object and its
  provenance.

Call this **reference/attach** in the product, not “citation,” so it is never
confused with citing external literature.

## Put infrastructure where it belongs

Workspace connectors, keys, data-source attachment, MCP configuration, and similar setup live in **Settings & workspace connections**. They are not a primary research navigation item.

## Preserve trust without ceremonial gates

Ask for an explicit approval only before an external transfer or order, a material cost threshold, or publishing/overwriting a shared project record. Quality gates still halt a run when the evidence says they should; their override and rationale are recorded.

## Make capability claims testable; retain capability choices

Every report must preserve an immutable run original, linked to its manifest and outputs, and support a reproducibility bundle/download. Server-backed report editing, accepted AI diffs, version history, and multi-format export remain retained product capabilities. Their delivery sequence requires an explicit product decision; this document does not cancel or postpone them. Until their API and persistence contract exist, the interface must not claim they are already deployed.

Models must visibly distinguish **validated predictive model**, **project-adapted model**, and **heuristic method**. A heuristic or unvalidated model must never appear to have held-out validation or to be a decision gate.
