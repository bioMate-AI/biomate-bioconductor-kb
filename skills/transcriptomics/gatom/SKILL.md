---
name: bioconductor-gatom
description: This package implements a metabolic network analysis pipeline to identify an active metabolic module based on high throughput data. The pipeline takes as input transcriptional and/or metabolic data and finds a metabolic subnetwork (module) most regulated between the two conditions of interest. The package further provides functions for module post-processing, annotation and visualization.
when_to_use: Use when: Using gatom package with gatom; Differential expression analysis (gatom). Not for: Requires R ≥ 4.3.0
user-invocable: false
---

# gatom

## Workflows

### Standard Workflow

Identify an active metabolic module from paired transcriptomics and metabolomics differential expression data using atom-level topology.

```r
library(gatom)
library(mwcsr)

# 1. Read user input files from the working directory
data("gene.de.rawEx")
data("met.de.rawEx")

# 2. Download/load the required network and annotation databases
data("networkEx")
data("met.kegg.dbEx")
data("org.Mm.eg.gatom.annoEx")

# 3. Construct the metabolic graph with atom-level topology
g <- makeMetabolicGraph(
  network = networkEx, 
  topology = "atoms", 
  org.gatom.anno = org.Mm.eg.gatom.annoEx, 
  gene.de = gene.de.rawEx, 
  met.db = met.kegg.dbEx, 
  met.de = met.de.rawEx
)

# 4. Score the graph nodes and edges
gs <- scoreGraph(g, k.gene = 25, k.met = 25)

# 5. Initialize the solver
solver <- rnc_solver()

# 6. Solve the maximum weight connected subgraph problem
res <- solve_mwcsp(solver, gs)
m <- res$graph

# 7. Visualize and save the module
saveModuleToHtml(module = m, file = tempfile(fileext = ".html"))
```
Input: Gene and metabolite differential expression data frames, network database, and organism annotation. Output: An active metabolic subnetwork saved as an HTML widget.

### Lipidomics Metabolite Level Active Module

Identify an active metabolic module from lipidomics data using metabolite-level topology and abbreviate lipid labels for readability.

```r
library(gatom)
library(mwcsr)

# 1. Read the declared user input file from the working directory
met.de.lipids <- data.table::fread("https://artyomovlab.wustl.edu/publications/supp_materials/GATOM/Ctrl.vs.HighFat.lipid.de.csv")

# 2. Download/load the required network and annotation databases
network.lipids <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/network.rhea.lipids.rds"))
met.lipids.db <- readRDS(url("http://artyomovlab.wustl.edu/publications/supp_materials/GATOM/met.lipids.db.rds"))
data("org.Mm.eg.gatom.annoEx")

# 3. Construct the metabolic graph with metabolite-level topology
lg <- makeMetabolicGraph(
  network = network.lipids, 
  topology = "metabolites", 
  org.gatom.anno = org.Mm.eg.gatom.annoEx, 
  gene.de = NULL, 
  met.db = met.lipids.db, 
  met.de = met.de.lipids
)

# 4. Score the graph
lgs <- scoreGraph(lg, k.gene = NULL, k.met = 50)

# 5. Solve the maximum weight connected subgraph problem
solver <- rnc_solver()
sol <- solve_mwcsp(solver, lgs)
lm <- sol$graph

# 6. Abbreviate metabolite labels for improved readability
lm1 <- abbreviateLabels(lm, orig.names = TRUE, abbrev.names = TRUE)

# 7. Visualize the resulting module (creates the widget object)
widget <- createShinyCyJSWidget(lm1)

# 8. Save meaningful results to output files
saveModuleToPdf(lm1, file = tempfile(fileext = ".pdf"))
```
Input: Lipidomics differential abundance data and lipid network database. Output: A metabolite-level active subnetwork with abbreviated labels.

## When to Use
- Identifying active metabolic subnetworks (modules) by integrating paired transcriptomics and metabolomics differential expression data.
- Analyzing lipidomics datasets using metabolite-level topology networks (e.g., Rhea lipid subnetwork) and abbreviating lipid names with `abbreviateLabels()`.
- Finding active modules when only gene expression data or only metabolomics data is available by setting the missing data parameter to `NULL`.

## When NOT to Use
- For standard differential expression analysis of RNA-seq data alone, use `DESeq2` or `edgeR` because `gatom` is designed to find connected subnetworks from pre-calculated differential expression statistics.
- For general non-metabolic protein-protein interaction network analysis, use `BioNet` or other generic network packages.

## Data Requirements
- Gene differential expression data frame containing columns for gene ID, p-value (`pval`), and log2 fold change (`log2FC`).
- Metabolite differential abundance data frame containing columns for metabolite ID, p-value (`pval`), and log2 fold change (`log2FC`).
- Organism-specific enzyme annotations and a global reaction network object (e.g., KEGG, Rhea, or Combined).

## Key Parameters
- **topology** ("atoms"): Network topology type, either `"atoms"` (atom-level) or `"metabolites"` (metabolite-level).
- **k.gene** (25): Scoring parameter controlling the size of the module based on gene significance.
- **k.met** (25): Scoring parameter controlling the size of the module based on metabolite significance.
- **keepReactionsWithoutEnzymes** (FALSE): Logical indicating whether to preserve non-enzymatic reactions in the constructed graph.
- **orig.names** (TRUE): Logical parameter for `abbreviateLabels` to keep original names.
- **abbrev.names** (TRUE): Logical parameter for `abbreviateLabels` to use abbreviated names.

## Best Practices
- Use the exact solver `virgo_solver()` (which requires Java and CPLEX) for high-quality, optimal active module identification instead of heuristic solvers.
- For combined, Rhea, and lipid networks, provide supplementary gene-to-reaction mapping files (`gene2reaction.extra`) to improve network coverage.
- Adjust the scoring parameters `k.gene` and `k.met` to control the size of the resulting module (higher values yield larger modules).

## Common Pitfalls
- *Missing Java/CPLEX for Virgo*: Attempting to use `virgo_solver()` without Java or CPLEX installed will fail; fix by falling back to `rnc_solver()` or installing dependencies.
- *Unmatched Metabolite IDs*: If metabolite IDs in the differential expression table do not match the network database (e.g., HMDB vs ChEBI), mapping will fail; fix by ensuring the correct database mapping is loaded.

## Alternatives
- `BioNet` for general active subnetwork search on protein-protein interaction networks.
- `fgsea` for standard pathway enrichment analysis without network topology.

## Citations
- Alexey Sergushichev et al. (2016). GAM: a web-service for integrated transcriptional and metabolic network analysis. Nucleic Acids Research.
- Mariia Emelianova et al. (2022). gatom: an R package for active metabolic module identification.

## References
- Homepage: bioconductor.org/packages/gatom
- Vignette: bioconductor.org/packages/release/bioc/vignettes/gatom/inst/doc/gatom.html
