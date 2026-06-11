#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BioNERO — module_preservation
// Assess the evolutionary conservation of coexpression modules between different species using orthology data.
// Input: zma.se, osa.se, og.zma.osa
// Container: quay.io/biocontainers/bioconductor-bionero:1.18.0--r45hdfd78af_0
// R packages: BioNERO, SummarizedExperiment
// Bioconductor: 3.20 | R: 4.4
// Requires: BioNERO, SummarizedExperiment
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Collapse gene-level expression to orthogroup-level using exp_genes2orthogroups()
//  * 2. [Core Analysis] Preprocess orthogroup expression data using exp_preprocess()
//  * 3. [Core Analysis] Determine scale-free topology fit power for each species using SFT_fit()
//  * 4. [Core Analysis] Infer gene coexpression networks for each species using exp2gcn()
//  * 5. [Core Analysis] Calculate module preservation statistics using module_preservation() with the NetRep algorithm

nextflow.enable.dsl = 2

process BIOC_BIONERO_MODULE_PRESERVATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("BioNERO", "SummarizedExperiment")
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
    library(BioNERO)
    
    # Set seed for reproducibility
    set.seed(123)
    
    # Read user input files from the working directory
    osa.se <- readRDS("osa.se")
    zma.se <- readRDS("zma.se")
    og.zma.osa <- readRDS("og.zma.osa")
    
    # Store SummarizedExperiment objects in a list
    zma_osa_list <- list(osa = osa.se, zma = zma.se)
    
    # Collapse gene-level expression to orthogroup-level
    ortho_exp <- exp_genes2orthogroups(zma_osa_list, og.zma.osa, summarize = "mean")
    
    # Preprocess data
    ortho_exp <- lapply(ortho_exp, exp_preprocess, variance_filter=TRUE, n=1000)
    
    # Calculate SFT power
    power_ortho <- lapply(ortho_exp, SFT_fit, cor_method="pearson")
    
    # Infer GCNs
    gcns <- lapply(seq_along(power_ortho), function(n) exp2gcn(ortho_exp[[n]], SFTpower = power_ortho[[n]]\$power, cor_method = "pearson") )
    
    # Calculate module preservation statistics
    pres <- module_preservation(ortho_exp, ref_net = gcns[[1]], test_net = gcns[[2]], algorithm = "netrep")
    
    # Save meaningful results to the working directory
    saveRDS(ortho_exp, "ortho_exp_preprocessed.rds")
    saveRDS(power_ortho, "power_ortho.rds")
    saveRDS(gcns, "gcns.rds")
    saveRDS(pres, "module_preservation_results.rds")

    writeLines(c(
        '"BIOC_BIONERO_MODULE_PRESERVATION":',
        paste0('    BioNERO: ', as.character(packageVersion('BioNERO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_module_preservation.csv versions.yml
    """
}

workflow BIOC_BIONERO_MODULE_PRESERVATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ zma.se, osa.se, og.zma.osa ] ]

    main:
    BIOC_BIONERO_MODULE_PRESERVATION(ch_input)

    emit:
    tables   = BIOC_BIONERO_MODULE_PRESERVATION.out.tables
    plots    = BIOC_BIONERO_MODULE_PRESERVATION.out.plots
    objects  = BIOC_BIONERO_MODULE_PRESERVATION.out.objects
    versions = BIOC_BIONERO_MODULE_PRESERVATION.out.versions
}
