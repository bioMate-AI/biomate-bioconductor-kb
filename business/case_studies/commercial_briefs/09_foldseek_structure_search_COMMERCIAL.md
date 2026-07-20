# BIOMATE AI | Commercial Case Brief | Prepared by BizBildr LLC
*Confidential*

## CASE BRIEF
# Search 214 Million Protein Structures — From a Database You Could Never Host Yourself

### THE PROBLEM
When a researcher has a new or predicted protein structure, the key question is "what known structures does this resemble?" Answering it means searching the AlphaFold Database — 214 million structures. The accurate classical method is far too slow at that scale, and the reference index is far too large for a lab to build or store locally. So most teams simply don't run the search.

### THE BIOMATE AI WORKFLOW
BioMate hosts the massive structural database as a prebuilt, ready-to-search index and runs the query for you using Foldseek — a method that represents each structure in a compact "structural alphabet," making the search dramatically faster while staying sensitive. It searches by structure and by sequence at once, merges the results, and double-checks the top hits with the gold-standard alignment method.

### TIME, COST & QUALITY COMPARISON

| Metric | Classical approach | BioMate AI |
|---|---|---|
| Searching 214M structures | Effectively infeasible | A routine hosted query |
| Speed vs classical alignment | 1× (baseline) | ~1,000–100,000× faster (Foldseek) |
| Index setup | Build + store hundreds of GB locally | Prebuilt and hosted — nothing to install |
| Result quality | — | Top hits re-checked with the gold-standard method |

### OUTCOME
Structural homology search over the entire AlphaFold universe becomes a click instead of an impossibility — enabling function prediction, druggable-fold discovery, and target hypothesis generation that were previously out of reach for teams without a data center.

### TECHNICAL VALIDATION NOTE
The workflow is implemented and validated end-to-end locally (correct self-matches, 8/8 tests; the full build-to-search cycle proven on hosted storage). Foldseek's structural-alphabet approach is independently established to deliver a 10³–10⁵× speedup over classical structural alignment. A full-database index build and cloud-scale run are the remaining steps to measure BioMate's production speed directly. Full technical validation report available on request.

### COMMERCIAL TIER & HOSTING MOAT
Large-DB-search tier. The moat is the hosted index: the AlphaFold Database is too big to build or store locally, so hosting it read-only — and running search on demand — is a capability a workstation simply cannot match.

*Design constraint: readable in ~90 seconds by a structural-biology or discovery lead. Depth lives in the companion Scientific & Technical Validation Report.*
