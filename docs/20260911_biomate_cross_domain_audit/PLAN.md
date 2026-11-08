# BioMate-wide reasoning and workflow audit

Scope: existing BioMate backend/chat behavior, separate from the experimental immune model. The shared evidence service described in the reasoning plan is not yet implemented; these tests establish the current baseline.

The live dev health endpoint reports API/AI available and Galaxy connected. Use the repository's dedicated E2E fixture account, separate sessions per test, and only fictional supplied results or public research-method literature. No collaborator/patient data and no outbound messages to collaborators. No large workflow dispatch in this first interpretation/retrieval batch.

## Collaboration mapping

Located: Zhejiang People's Hospital drug-discovery pilot, the China hospital/pharma requirements, and Zhao/Zhi/Liu faculty workflows. The named faculty documents refer to UTHealth/BCM, not China-based appointments. The exact China faculty list is awaiting user clarification; do not attribute provisional workflows to specific Chinese faculty.

## First live batch

The eight prompts and prespecified checks are in `cases.json`: ADMET margins; docking versus measured potency; PBPK unit conversion; bulk RNA differential-expression thresholds; GWAS/single-cell causal interpretation; rare-disease VUS/splicing interpretation; cryo-EM mechanism limits; evidence retrieval and claim-linked citations.

Run through the actual `/api/chat/stream` endpoint, capture SSE tool events and final payloads, and grade scientific interpretation separately from transport success. Supplied-results tests are not fresh executions of ADMET, PBPK or sequencing workflows. Do not use catalog presence, a generated card, or a citation list as proof of computation or evidentiary support.

## Subsequent workflow layer

Inspect live catalog/rationale endpoints for the documented faculty chains. A metadata check is not a real-data chain run. Record execution evidence separately and prioritize one bounded complete pipeline with suitable fixtures. End-to-end app/UI execution requires a completed run, readable outputs, faithful findings, source provenance, and consistent follow-up interpretation.

Save raw results, limitations, failures and next tasks. The immune raw-count-to-model test continues separately and must not be presented as BioMate-wide end-to-end coverage.

## Executed extension

Added CN01 hospital biomarker/batch confounding and CN02 tumor peptide/HLA interpretation. Dispatched one three-compound ADMET run and followed its exact ID through terminal compute status, output downloads and findings. See RESULTS.md for the failed output-delivery gate. No DESeq2 compute was dispatched without file bindings.
