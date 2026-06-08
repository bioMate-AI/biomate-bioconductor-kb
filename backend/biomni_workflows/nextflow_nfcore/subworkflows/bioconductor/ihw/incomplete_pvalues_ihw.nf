#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: IHW — incomplete_pvalues_ihw
// Perform independent hypothesis weighting when only a subset of low p-values is reported or available.
// Input: sim.csv, simSub.csv
// Container: quay.io/biocontainers/bioconductor-ihw:1.38.0--r45hdfd78af_0
// Requires: IHW, dplyr, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Discretize the continuous covariate into bins using groups_by_filter
//  * 2. [Core Analysis] Calculate the total number of hypotheses per bin using table
//  * 3. [Core Analysis] Run IHW on the filtered dataset by specifying the group factor and passing the table of group sizes to m_groups

nextflow.enable.dsl = 2

process BIOC_IHW_INCOMPLETE_PVALUES_IHW {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(dplyr)
    library(IHW)
    library(ggplot2)
    
    # Read the user-provided input files from the working directory
    sim <- read.csv("sim.csv")
    simSub <- read.csv("simSub.csv")
    
    # Ensure the 'reported' column exists in the full dataset.
    # If it is not already present, we reconstruct it by identifying which 
    # hypotheses in the full dataset 'sim' are present in the reported subset 'simSub'.
    if (!"reported" %in% colnames(sim)) {
      threshold <- max(simSub\$p, na.rm = TRUE)
      sim\$reported <- sim\$p <= threshold
    }
    
    # === DOCUMENTED CODE ===
    nbins <- 20
    sim <- mutate(sim, group = groups_by_filter(X, nbins))
    m_groups  <- table(sim\$group)
    ihwS <- ihw(p ~ group, alpha = 0.1, data = filter(sim, reported), m_groups = m_groups)
    ihwS
    # === END DOCUMENTED CODE ===
    
    # Write meaningful output files
    # 1. Save the complete IHW result object as an RDS file
    saveRDS(ihwS, "ihw_result.rds")
    
    # 2. Export the results (including adjusted p-values and weights) as a CSV table
    ihw_df <- as.data.frame(ihwS)
    write.csv(ihw_df, "ihw_results.csv", row.names = FALSE)
    
    # 3. Generate and save diagnostic plots to a PDF file
    pdf("ihw_plots.pdf", width = 8, height = 6)
    tryCatch({
      print(plot(ihwS))
    }, error = function(e) {
      message("Could not generate weights plot: ", e\$message)
    })
    
    tryCatch({
      print(plot(ihwS, what = "decisionboundary"))
    }, error = function(e) {
      message("Could not generate decision boundary plot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_IHW_INCOMPLETE_PVALUES_IHW":',
        paste0('    IHW: ', as.character(packageVersion('IHW')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_incomplete_pvalues_ihw.csv versions.yml
    """
}

workflow BIOC_IHW_INCOMPLETE_PVALUES_IHW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sim.csv, simSub.csv ] ]

    main:
    BIOC_IHW_INCOMPLETE_PVALUES_IHW(ch_input)

    emit:
    tables   = BIOC_IHW_INCOMPLETE_PVALUES_IHW.out.tables
    plots    = BIOC_IHW_INCOMPLETE_PVALUES_IHW.out.plots
    objects  = BIOC_IHW_INCOMPLETE_PVALUES_IHW.out.objects
    versions = BIOC_IHW_INCOMPLETE_PVALUES_IHW.out.versions
}
