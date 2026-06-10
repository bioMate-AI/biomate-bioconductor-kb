#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: apComplex — protein_complex_estimation
// Estimate protein complex membership from AP-MS bait-hit data, merge initial subgraphs using sensitivity/specificity parameters, and sort them into topological c
// Input: apEX
// Container: quay.io/biocontainers/bioconductor-apcomplex:2.76.0--r45hdfd78af_0
// R packages: apComplex
// Bioconductor: 3.20 | R: 4.4
// Requires: apComplex
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Find initial maximal BH-complete subgraphs using bhmaxSubgraph
//  * 2. [Core Analysis] Merge complexes using mergeComplexes based on sensitivity and specificity parameters
//  * 3. [Core Analysis] Alternatively, run both steps together using findComplexes
//  * 4. [Core Analysis] Sort the estimated complexes into MBME, SBMH, and UnRBB components using sortComplexes

nextflow.enable.dsl = 2

process BIOC_APCOMPLEX_PROTEIN_COMPLEX_ESTIMATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("apComplex")
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
    
    # Load required library
    library(apComplex)
    
    # Read input file 'apEX' from the working directory
    # We support both CSV and RDS formats
    if (file.exists("apEX.csv")) {
      apEX <- as.matrix(read.csv("apEX.csv", row.names = 1, check.names = FALSE))
    } else if (file.exists("apEX.rds")) {
      apEX <- readRDS("apEX.rds")
    } else {
      stop("Error: Input file 'apEX.csv' or 'apEX.rds' not found in the working directory.")
    }
    
    # Ensure apEX is a matrix
    apEX <- as.matrix(apEX)
    
    # 1. Find initial maximal BH-complete subgraphs
    PCMG0 <- bhmaxSubgraph(apEX)
    saveRDS(PCMG0, "PCMG0.rds")
    
    # 2. Merge complexes based on sensitivity and specificity parameters
    PCMG1 <- mergeComplexes(PCMG0, apEX, sensitivity = 0.7, specificity = 0.75)
    saveRDS(PCMG1, "PCMG1.rds")
    
    # 3. Alternatively, run both steps together
    PCMG2 <- findComplexes(apEX, sensitivity = 0.7, specificity = 0.75)
    saveRDS(PCMG2, "PCMG2.rds")
    
    # 4. Sort the estimated complexes into MBME, SBMH, and UnRBB components
    sorted_complexes <- sortComplexes(PCMG2, adjMat = apEX)
    saveRDS(sorted_complexes, "sorted_complexes.rds")
    
    # Write a text summary of the sorted complexes
    sink("sorted_complexes_summary.txt")
    cat("=== Sorted Complexes Summary ===\n\n")
    for (category in names(sorted_complexes)) {
      cat("Category:", category, "\n")
      cat("-------------------------\n")
      sub_list <- sorted_complexes[[category]]
      if (length(sub_list) == 0) {
        cat("  None\n")
      } else {
        for (comp_name in names(sub_list)) {
          cat("  ", comp_name, ": ", paste(sub_list[[comp_name]], collapse = ", "), "\n", sep = "")
        }
      }
      cat("\n")
    }
    sink()
    
    # Write a CSV representation of the sorted complexes for downstream analysis
    complex_df <- data.frame(Category = character(), Complex = character(), Protein = character(), stringsAsFactors = FALSE)
    for (category in names(sorted_complexes)) {
      sub_list <- sorted_complexes[[category]]
      for (comp_name in names(sub_list)) {
        proteins <- sub_list[[comp_name]]
        tmp_df <- data.frame(
          Category = category,
          Complex = comp_name,
          Protein = proteins,
          stringsAsFactors = FALSE
        )
        complex_df <- rbind(complex_df, tmp_df)
      }
    }
    write.csv(complex_df, "sorted_complexes.csv", row.names = FALSE)
    
    cat("Workflow completed successfully. Outputs saved to PCMG0.rds, PCMG1.rds, PCMG2.rds, sorted_complexes.rds, sorted_complexes_summary.txt, and sorted_complexes.csv.\n")

    writeLines(c(
        '"BIOC_APCOMPLEX_PROTEIN_COMPLEX_ESTIMATION":',
        paste0('    apComplex: ', as.character(packageVersion('apComplex')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_complex_estimation.csv versions.yml
    """
}

workflow BIOC_APCOMPLEX_PROTEIN_COMPLEX_ESTIMATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ apEX ] ]

    main:
    BIOC_APCOMPLEX_PROTEIN_COMPLEX_ESTIMATION(ch_input)

    emit:
    tables   = BIOC_APCOMPLEX_PROTEIN_COMPLEX_ESTIMATION.out.tables
    plots    = BIOC_APCOMPLEX_PROTEIN_COMPLEX_ESTIMATION.out.plots
    objects  = BIOC_APCOMPLEX_PROTEIN_COMPLEX_ESTIMATION.out.objects
    versions = BIOC_APCOMPLEX_PROTEIN_COMPLEX_ESTIMATION.out.versions
}
