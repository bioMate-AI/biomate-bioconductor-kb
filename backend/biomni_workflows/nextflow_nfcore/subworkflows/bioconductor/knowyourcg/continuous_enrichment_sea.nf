#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: knowyourcg — continuous_enrichment_sea
// Perform Set Enrichment Analysis (SEA) using a continuous query (e.g., beta values or continuous genomic metrics) against discrete or continuous databases.
// Input: beta_values
// Container: quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0
// R packages: knowYourCG, sesame
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KNOWYOURCG_CONTINUOUS_ENRICHMENT_SEA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-knowyourcg:1.6.3--r45h01b2380_0"

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
    .bm_deps <- c("knowYourCG", "sesame")
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
    library(knowYourCG)
    library(sesame)
    
    # Stage 1: Retrieve continuous query (TSS) and run Set Enrichment Analysis against seqContextN
    message("Running Set Enrichment Analysis for TSS query...")
    query <- getDBs("KYCG.MM285.designGroup")[["TSS"]]
    sesameDataCache(data_titles = c("KYCG.MM285.seqContextN.20210630"))
    res <- testEnrichmentSEA(query, "MM285.seqContextN")
    
    # Save TSS enrichment results
    write.csv(res, "enrichment_sea_tss_seqContextN.csv", row.names = TRUE)
    saveRDS(res, "enrichment_sea_tss_seqContextN.rds")
    
    # Stage 2: Retrieve continuous query (beta values) from user input and run Set Enrichment Analysis against chromHMM
    message("Loading user-provided beta values...")
    if (file.exists("beta_values")) {
      beta_values <- tryCatch({
        readRDS("beta_values")
      }, error = function(e) {
        tryCatch({
          df <- read.csv("beta_values", header = TRUE, row.names = 1)
          setNames(as.numeric(df[[1]]), rownames(df))
        }, error = function(e2) {
          df <- read.table("beta_values", header = TRUE, row.names = 1)
          setNames(as.numeric(df[[1]]), rownames(df))
        })
      })
    } else if (file.exists("beta_values.rds")) {
      beta_values <- readRDS("beta_values.rds")
    } else if (file.exists("beta_values.csv")) {
      df <- read.csv("beta_values.csv", header = TRUE, row.names = 1)
      beta_values <- setNames(as.numeric(df[[1]]), rownames(df))
    } else {
      stop("Required input file 'beta_values' not found in the working directory.")
    }
    
    message("Running Set Enrichment Analysis for beta values...")
    res <- testEnrichmentSEA(beta_values, "MM285.chromHMM")
    
    # Save beta values enrichment results
    write.csv(res, "enrichment_sea_betas_chromHMM.csv", row.names = TRUE)
    saveRDS(res, "enrichment_sea_betas_chromHMM.rds")
    message("Analysis complete. Results saved successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KNOWYOURCG_CONTINUOUS_ENRICHMENT_SEA":
        knowyourcg: \$(Rscript -e 'cat(as.character(packageVersion("knowyourcg")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_continuous_enrichment_sea.csv versions.yml
    """
}

workflow BIOC_KNOWYOURCG_CONTINUOUS_ENRICHMENT_SEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ beta_values ] ]

    main:
    BIOC_KNOWYOURCG_CONTINUOUS_ENRICHMENT_SEA(ch_input)

    emit:
    tables   = BIOC_KNOWYOURCG_CONTINUOUS_ENRICHMENT_SEA.out.tables
    plots    = BIOC_KNOWYOURCG_CONTINUOUS_ENRICHMENT_SEA.out.plots
    objects  = BIOC_KNOWYOURCG_CONTINUOUS_ENRICHMENT_SEA.out.objects
    versions = BIOC_KNOWYOURCG_CONTINUOUS_ENRICHMENT_SEA.out.versions
}
