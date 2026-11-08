# Targeted supplementary structure recovery — 29 October 2026

## Matched-pair source: K2-124d856a78cc

The primary article explicitly pairs **1c with 5c**. Its Experimental Section names 5c as `(S)-2-Acetamido-3-(4-methoxyphenyl)-N-((S)-1-oxo-1-((2-oxo-2-phenylethyl)amino)-3-phenylpropan-2-yl)propanamide`; this is a source name, not a newly generated graph. Its crystal deposit is **CCDC 2556094**. Neither resource has been converted into SMILES here. The named 1a–1g/5a–5g pairs combine ring opening with O-methylation.

The assay is apical-to-basolateral Caco-2 transport with quinidine, benzbromarone and sulfasalazine suppressing efflux. Lipophilicity uses octanol/PBS partitioning; solubility uses dried DMSO stock followed by PBS reconstitution. Thus source data must preserve three distinct endpoints. Exact per-compound permeability values and paired graphs remain uninspected; none was read from plotted points. [Primary article: Experimental Section, compound 5c and assay methods](https://pmc.ncbi.nlm.nih.gov/articles/PMC13370866/).

### Actual public access outcomes

- The article's publisher CSV link returned HTTP 403 during the preceding review.
- Its actual PMC HTML link is `https://pmc.ncbi.nlm.nih.gov/articles/instance/13370866/bin/jm6c00830_si_001.csv`. The web reader returned a browser challenge. An ordinary public HTTP fetch returned an HTML download-preparation/proof-of-work page, **not CSV**. It is retained at `/tmp/jm6c00830_si_001.download`; it must not be mistaken for recovered data. No challenge-solving or cookie manipulation was attempted.
- Public OA metadata requests at the NCBI and PMC `utils/oa/oa.fcgi` routes returned 404. This does not establish that the article lacks an OA package.
- A search for the exact supplement and an ACS Figshare copy did not identify an accessible alternate file.

The next necessary evidence is the publisher-supplied CSV rows for **1c and 5c**, followed by exact stereochemical-structure and endpoint qualification. A synthesized SMILES from the name would be new reconstruction and cannot replace the unavailable original row. This review did not establish a complete paired structure/measurement record.

## Fallback inspection: K2-4c761c0659ae

The alternate primary paper confirms **2b (Ile)** versus **3b (Ala)** and the different cyclization temperature requirements. Its supporting-information link `ol6c01073_si_001.pdf` returned 403; the figure-3 page was unavailable through the web reader. Therefore complete stereochemical structures, timing and conversion traces remain unqualified. This reaction observation cannot supply a permeability or proteolytic-stability prior. [Primary paper: substrate scope, Figure 3 and Figures S10–S11](https://pmc.ncbi.nlm.nih.gov/articles/PMC13140135/).

Both candidates remain `AI_ASSISTED_CANDIDATE`, with `method_prior_eligible=false`. No original records changed, no chemical parsing, scientific aggregation, local tests, paid API calls or cloud jobs were performed. The previously verified retained-text hashes and exact quotation spans remain in `20261029_literature_recovery_candidates.json`.
