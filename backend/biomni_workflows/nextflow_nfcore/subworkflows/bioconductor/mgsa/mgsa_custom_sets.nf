#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mgsa — mgsa_custom_sets
// Perform model-based gene set enrichment analysis using custom-defined gene sets.
// Input: study_genes.txt, custom_sets.rds
// Container: quay.io/biocontainers/bioconductor-mgsa:1.58.0--r45h01b2380_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mgsa
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Run MGSA directly with a list of custom sets, or pre-index them by creating an MgsaSets object
//  * 2. [Core Analysis] Run MGSA using mgsa with the pre-indexed sets for multiple observations

nextflow.enable.dsl = 2

process BIOC_MGSA_MGSA_CUSTOM_SETS {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load the required library
    library(mgsa)
    
    # Set seed for reproducibility of the MCMC fitting
    set.seed(42)
    
    # 1. Read user input files
    if (!file.exists("study_genes.txt")) {
      stop("Error: study_genes.txt not found in the working directory.")
    }
    if (!file.exists("custom_sets.rds")) {
      stop("Error: custom_sets.rds not found in the working directory.")
    }
    
    # Read study genes (character vector of observed genes)
    study_genes <- readLines("study_genes.txt")
    study_genes <- trimws(study_genes)
    study_genes <- study_genes[study_genes != ""]
    
    # Read custom gene sets (list of custom gene sets)
    custom_sets <- readRDS("custom_sets.rds")
    
    # 2. Run MGSA directly with a list of custom sets
    # Documented: mgsa( c("A", "B"), list(set1=LETTERS[1:3], set2=LETTERS[2:5]) )
    fit_direct <- mgsa( study_genes, custom_sets )
    
    # Extract and save results from the direct run
    res_direct <- setsResults(fit_direct)
    write.csv(res_direct, "mgsa_results_direct.csv", row.names = TRUE)
    
    # 3. Pre-index the sets by creating an MgsaSets object
    # Documented: myset = new( "MgsaSets", sets=list(set1=LETTERS[1:3], set2=LETTERS[2:5]) )
    myset = new( "MgsaSets", sets=custom_sets )
    
    # 4. Run MGSA using mgsa with the pre-indexed sets for multiple observations
    # Documented:
    # mgsa(c("A", "B"), myset)
    # mgsa(c("B", "C"), myset)
    # We define two observations from our study genes to represent multiple observations.
    obs1 <- study_genes
    obs2 <- study_genes[1:max(1, floor(length(study_genes) / 2))]
    
    fit_indexed_obs1 <- mgsa(obs1, myset)
    fit_indexed_obs2 <- mgsa(obs2, myset)
    
    # Extract and save results from the indexed runs
    res_indexed_obs1 <- setsResults(fit_indexed_obs1)
    res_indexed_obs2 <- setsResults(fit_indexed_obs2)
    
    write.csv(res_indexed_obs1, "mgsa_results_indexed_obs1.csv", row.names = TRUE)
    write.csv(res_indexed_obs2, "mgsa_results_indexed_obs2.csv", row.names = TRUE)
    
    # Save the fit objects as RDS files
    saveRDS(fit_direct, "mgsa_fit_direct.rds")
    saveRDS(fit_indexed_obs1, "mgsa_fit_indexed_obs1.rds")
    saveRDS(fit_indexed_obs2, "mgsa_fit_indexed_obs2.rds")
    
    # Generate diagnostic plots for the fits
    pdf("mgsa_plot_direct.pdf", width = 8, height = 6)
    plot(fit_direct)
    dev.off()
    
    pdf("mgsa_plot_indexed_obs1.pdf", width = 8, height = 6)
    plot(fit_indexed_obs1)
    dev.off()

    writeLines(c(
        '"BIOC_MGSA_MGSA_CUSTOM_SETS":',
        paste0('    mgsa: ', as.character(packageVersion('mgsa')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mgsa_custom_sets.csv versions.yml
    """
}

workflow BIOC_MGSA_MGSA_CUSTOM_SETS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ study_genes.txt, custom_sets.rds ] ]

    main:
    BIOC_MGSA_MGSA_CUSTOM_SETS(ch_input)

    emit:
    tables   = BIOC_MGSA_MGSA_CUSTOM_SETS.out.tables
    plots    = BIOC_MGSA_MGSA_CUSTOM_SETS.out.plots
    objects  = BIOC_MGSA_MGSA_CUSTOM_SETS.out.objects
    versions = BIOC_MGSA_MGSA_CUSTOM_SETS.out.versions
}
