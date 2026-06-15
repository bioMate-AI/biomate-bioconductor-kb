---
name: bioconductor-bandle
description: The Bandle package enables the analysis and visualisation of differential localisation experiments using mass-spectrometry data. Experimental methods supported include dynamic LOPIT-DC, hyperLOPIT, Dynamic Organellar Maps, Dynamic PCP. It provides Bioconductor infrastructure to analyse these data.
when_to_use: Use when: Analysing differential localisation experiments with BANDLE: Vignette 1; Analysing differential localisation experiments with BANDLE: Vignette 2; Proteomics quantification (bandle); Quality control and preprocessing (bandle). Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# bandle

## Workflows

### Standard Workflow

Perform differential subcellular localisation analysis on mass-spectrometry-based spatial proteomics data across two conditions.

```r
library(bandle)
library(pRolocdata)
data("tan2009r1")

# 1. Load User Input and Extract Common Features (simulated here)
tansim <- sim_dynamic(object = tan2009r1, numRep = 6L, numDyn = 100L)
control <- tansim$lopitrep[1:3]
treatment <- tansim$lopitrep[4:6]

# 2. Fit Gaussian Processes to Marker Profiles
gpParams <- lapply(tansim$lopitrep, function(x) fitGPmaternPC(x))

# 3. Set Up and Check Dirichlet Prior
K <- length(getMarkerClasses(tansim$lopitrep[[1]], fcol = "markers"))
dirPrior <- diag(rep(1, K)) + matrix(0.001, nrow = K, ncol = K)
predDirPrior <- prior_pred_dir(object = tansim$lopitrep[[1]], dirPrior = dirPrior, q = 15)

# 4. Run BANDLE MCMC
pc_prior <- matrix(rep(c(10, 60, 250), each = K), ncol = 3)
bandleres <- bandle(objectCond1 = control, objectCond2 = treatment, 
                    numIter = 100, burnin = 5L, thin = 1L, 
                    gpParams = gpParams, pcPrior = pc_prior, 
                    numChains = 3, dirPrior = dirPrior, seed = 1)

# 5. Assess MCMC Convergence
calculateGelman(bandleres)
plotOutliers(bandleres)

# 6. Extract Differential Localisation Probabilities
bandleres_opt <- bandleProcess(bandleres)
xx <- bandlePredict(control, treatment, params = bandleres_opt, fcol = "markers")
res_control <- xx[[1]]
res_treatment <- xx[[2]]
```
*Input: Replicated MSnSet objects for control and treatment conditions. Output: A list of MSnSet objects with appended subcellular allocation probabilities and differential localisation predictions.*

## When to Use
- Analyzing differential subcellular localisation of proteins across two conditions (e.g., control vs. treatment) using mass-spectrometry-based spatial proteomics data.
- Quantifying uncertainty in protein subcellular assignments using Bayesian posterior distributions.
- Fitting non-parametric regression functions to marker profiles using Gaussian processes with `fitGPmaternPC()`.

## When NOT to Use
- For standard differential expression/abundance analysis of proteins; use `MSstats` instead.
- For simple static subcellular localisation without a comparative/differential design; use `pRoloc` instead.

## Data Requirements
- Input data must be stored as `MSnSet` instances (from `MSnbase`).
- Requires replicate experiments for both conditions (e.g., control and treatment).
- Requires predefined marker proteins annotated in the feature data (e.g., `fcol = "markers"`).

## Key Parameters
- **objectCond1**: List of `MSnSet` objects for condition 1 (control).
- **objectCond2**: List of `MSnSet` objects for condition 2 (treatment).
- **numIter**: Number of MCMC iterations (typically 10,000).
- **burnin**: Number of burn-in iterations to discard (typically 5,000).
- **thin**: Thinning interval for MCMC sampling (typically 20).
- **gpParams**: Gaussian Process parameters obtained from `fitGPmaternPC()`.
- **pcPrior**: Penalised complexity prior matrix for the Gaussian Processes.
- **dirPrior**: Dirichlet prior matrix on the mixing weights.

## Best Practices
- Visually evaluate the fit of the Gaussian Processes to marker profiles using `plotGPmatern()` before running the main MCMC.
- Run at least 4 parallel chains and a high number of iterations (e.g., 10,000) to ensure robust posterior sampling.
- Assess MCMC convergence using `calculateGelman()` (ratios should be < 1.2) and `plotOutliers()` before interpreting results.
- Remove unconverged chains using standard subsetting (e.g., `bandleres[-2]`) before running `bandleProcess()`.

## Common Pitfalls
- Running too few MCMC iterations: Leads to poor convergence and unreliable probability estimates. Fix: Increase `numIter` to 10,000 and `burnin` to 5,000.
- Including unconverged chains in downstream analysis: Distorts posterior probability distributions. Fix: Subset the `bandleParams` object to exclude bad chains before processing.

## Alternatives
- `pRoloc`: For static (single-condition) spatial proteomics and organelle assignment.
- `MSnbase`: For basic mass spectrometry data structures and processing.

## Citations
- Crook et al. 2022, bioRxiv/journal (for BANDLE).
- Crook et al. 2018, PLOS Computational Biology (for TAGM).

## References
- Homepage: bioconductor.org/packages/bandle
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/bandle/inst/doc/vignette1-getting-started.html
