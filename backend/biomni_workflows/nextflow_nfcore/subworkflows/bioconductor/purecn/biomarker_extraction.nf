#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PureCN — biomarker_extraction
// Extract clinical biomarkers such as Tumor Mutational Burden (TMB) and Chromosomal Instability (CIN) from curated PureCN results.
// Input: Sample1_PureCN.rds, callable_status.bed
// Container: quay.io/biocontainers/bioconductor-purecn:2.16.0--r45hdfd78af_0
// R packages: PureCN, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: PureCN, rtracklayer
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Calculate tumor mutational burden (TMB) using callMutationBurden
//  * 2. [Core Analysis] Calculate chromosomal instability (CIN) using callCIN

nextflow.enable.dsl = 2

process BIOC_PURECN_BIOMARKER_EXTRACTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20-slim"

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
    .bm_deps <- c("PureCN", "rtracklayer")
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
    
    # Load required Bioconductor libraries
    library(PureCN)
    library(rtracklayer)
    
    # 1. Load the user-provided serialized PureCN output object
    ret <- readRDS("Sample1_PureCN.rds")
    
    # 2. Load the user-provided callable status BED file
    callableBed <- rtracklayer::import("callable_status.bed")
    
    # 3. Calculate Tumor Mutational Burden (TMB)
    # Using the exact documented function call and arguments
    tmb <- callMutationBurden(ret, callable = callableBed)
    
    # Write TMB results to a CSV file
    write.csv(tmb, file = "Sample1_TMB_results.csv", row.names = FALSE)
    
    # 4. Calculate Chromosomal Instability (CIN)
    # Using the exact documented function calls and arguments
    cin <- data.frame(
        cin = callCIN(ret, allele.specific = FALSE, reference.state = "normal"),
        cin.allele.specific = callCIN(ret, reference.state = "normal"),
        cin.ploidy.robust = callCIN(ret, allele.specific = FALSE),
        cin.allele.specific.ploidy.robust = callCIN(ret)
    )
    
    # Write CIN results to a CSV file
    write.csv(cin, file = "Sample1_CIN_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_PURECN_BIOMARKER_EXTRACTION":',
        paste0('    PureCN: ', as.character(packageVersion('PureCN')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomarker_extraction.csv versions.yml
    """
}

workflow BIOC_PURECN_BIOMARKER_EXTRACTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Sample1_PureCN.rds, callable_status.bed ] ]

    main:
    BIOC_PURECN_BIOMARKER_EXTRACTION(ch_input)

    emit:
    tables   = BIOC_PURECN_BIOMARKER_EXTRACTION.out.tables
    plots    = BIOC_PURECN_BIOMARKER_EXTRACTION.out.plots
    objects  = BIOC_PURECN_BIOMARKER_EXTRACTION.out.objects
    versions = BIOC_PURECN_BIOMARKER_EXTRACTION.out.versions
}
