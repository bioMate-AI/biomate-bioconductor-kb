#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MAGeCKFlute — mageck_rra_analysis
// Perform downstream quality control, visualization, and functional enrichment analysis on CRISPR screen results processed via the MAGeCK RRA (Robust Rank Aggrega
// Input: gene_summary.txt, sgrna_summary.txt
// Container: quay.io/biocontainers/bioconductor-mageckflute:2.9.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MAGeCKFlute
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read the RRA gene and sgRNA summary files
//  * 2. [Core Analysis] Run the FluteRRA pipeline to perform quality control, identify positively and negatively selected genes, and execute pathway enric

nextflow.enable.dsl = 2

process BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
    .bm_deps <- c("MAGeCKFlute")
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
    library(MAGeCKFlute)
    
    # Step 1: Read the RRA gene and sgRNA summary files from the working directory
    # These files must exist in the working directory as specified by the user input.
    gene_file <- "gene_summary.txt"
    sgrna_file <- "sgrna_summary.txt"
    
    if (!file.exists(gene_file)) {
      stop(paste("Required input file missing:", gene_file))
    }
    if (!file.exists(sgrna_file)) {
      stop(paste("Required input file missing:", sgrna_file))
    }
    
    gdata <- read.delim(gene_file, check.names = FALSE)
    sdata <- read.delim(sgrna_file, check.names = FALSE)
    
    # Step 2: Run the FluteRRA pipeline
    # This performs quality control, identifies positively and negatively selected genes,
    # and executes pathway enrichment analysis.
    rra_results <- FluteRRA(gdata, sdata, proj = "RRA_Project", organism = "hsa", outdir = "./")
    
    # Step 3: Save the returned results object for downstream inspection
    saveRDS(rra_results, file = "RRA_Project_results.rds")

    writeLines(c(
        '"BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS":',
        paste0('    MAGeCKFlute: ', as.character(packageVersion('MAGeCKFlute')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mageck_rra_analysis.csv versions.yml
    """
}

workflow BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_summary.txt, sgrna_summary.txt ] ]

    main:
    BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS.out.tables
    plots    = BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS.out.plots
    objects  = BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS.out.objects
    versions = BIOC_MAGECKFLUTE_MAGECK_RRA_ANALYSIS.out.versions
}
