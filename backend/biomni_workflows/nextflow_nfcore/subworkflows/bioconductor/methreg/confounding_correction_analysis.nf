#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MethReg — confounding_correction_analysis
// Extract residuals from DNA methylation and gene expression data to control for confounding variables (e.g., age, sex, batch effects) before fitting regulatory m
// Input: dnam_matrix.rds, gene_exp_matrix.rds, metadata.rds
// Container: quay.io/biocontainers/bioconductor-methreg:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MethReg, SummarizedExperiment, dplyr
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Extract residuals for gene expression data using get_residuals
//  * 2. [Visualization & Output] Convert DNA methylation matrix to a SummarizedExperiment using make_se_from_dnam_probes
//  * 3. [Core Analysis] Extract residuals for DNA methylation data using get_residuals
//  * 4. [Core Analysis] Fit robust linear interaction models on the residuals using interaction_model

nextflow.enable.dsl = 2

process BIOC_METHREG_CONFOUNDING_CORRECTION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("dplyr", "MethReg")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(dplyr)
    library(MethReg)
    
    # 1. Read the declared USER INPUT files from the working directory
    gene.exp.matrix <- readRDS("gene_exp_matrix.rds")
    dna.met.chr21 <- readRDS("dnam_matrix.rds")
    metadata <- readRDS("metadata.rds")
    
    # Convert gene expression matrix to a SummarizedExperiment object
    gene.exp.chr21 <- make_exp_se(
      exp = gene.exp.matrix,
      genome = "hg38",
      verbose = FALSE
    )
    
    # 2. Extract residuals for gene expression data using get_residuals
    gene.exp.chr21.residuals <- get_residuals(gene.exp.chr21, metadata) %>% as.matrix()
    
    # 3. Convert DNA methylation matrix to a SummarizedExperiment using make_se_from_dnam_probes
    dna.met.chr21 <- make_se_from_dnam_probes(
      dnam = dna.met.chr21,
      genome = "hg38",
      arrayType = "450k",
      betaToM = TRUE
    )
    
    # 4. Extract residuals for DNA methylation data using get_residuals
    dna.met.chr21.residuals <- get_residuals(dna.met.chr21, metadata) %>% as.matrix()
    
    # 5. Create the triplet dataset required for the interaction model
    triplet <- create_triplet_distance_based(
      region = dna.met.chr21,
      target.method = "genes.promoter.overlap",
      genome = "hg38",
      target.promoter.upstream.dist.tss = 2000,
      target.promoter.downstream.dist.tss = 2000,
      motif.search.window.size = 400,
      motif.search.p.cutoff = 1e-08,
      cores = 1
    )
    
    # 6. Fit robust linear interaction models on the residuals using interaction_model
    results <- interaction_model(
        triplet = triplet,
        dnam = dna.met.chr21.residuals,
        exp = gene.exp.chr21.residuals
    )
    
    # 7. Write named output files for the meaningful results
    saveRDS(gene.exp.chr21.residuals, "gene_exp_residuals.rds")
    saveRDS(dna.met.chr21.residuals, "dna_met_residuals.rds")
    saveRDS(triplet, "triplet.rds")
    saveRDS(results, "interaction_results.rds")
    write.csv(results, "interaction_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_METHREG_CONFOUNDING_CORRECTION_ANALYSIS":',
        paste0('    MethReg: ', as.character(packageVersion('MethReg')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_confounding_correction_analysis.csv versions.yml
    """
}

workflow BIOC_METHREG_CONFOUNDING_CORRECTION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dnam_matrix.rds, gene_exp_matrix.rds, metadata.rds ] ]

    main:
    BIOC_METHREG_CONFOUNDING_CORRECTION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHREG_CONFOUNDING_CORRECTION_ANALYSIS.out.tables
    plots    = BIOC_METHREG_CONFOUNDING_CORRECTION_ANALYSIS.out.plots
    objects  = BIOC_METHREG_CONFOUNDING_CORRECTION_ANALYSIS.out.objects
    versions = BIOC_METHREG_CONFOUNDING_CORRECTION_ANALYSIS.out.versions
}
