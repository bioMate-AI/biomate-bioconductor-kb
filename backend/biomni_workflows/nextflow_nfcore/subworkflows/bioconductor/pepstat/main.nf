#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pepStat — peptide_microarray_pipeline
// Perform a complete peptide microarray analysis from raw GPR files to normalized, smoothed positivity calls and visualizations.
// Input: gpr_samples/, mapping.csv, pep_info.csv
// Container: quay.io/biocontainers/bioconductor-pepstat:1.44.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Pviz, pepStat
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load raw GPR files and sample mapping metadata using makePeptideSet. 2. (Optional) Visualize spatial slide artifacts and residuals

nextflow.enable.dsl = 2

process BIOC_PEPSTAT_PEPTIDE_MICROARRAY_PIPELINE {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(pepStat)
    library(Pviz)
    
    # Define input paths as specified by the user
    mapFile <- "mapping.csv"
    dirToParse <- "gpr_samples"
    pepInfoFile <- "pep_info.csv"
    
    # Validate that required inputs exist
    if (!file.exists(mapFile)) {
      stop("Error: mapping.csv not found in the working directory.")
    }
    if (!dir.exists(dirToParse)) {
      stop("Error: gpr_samples/ directory not found in the working directory.")
    }
    if (!file.exists(pepInfoFile)) {
      stop("Error: pep_info.csv not found in the working directory.")
    }
    
    # 1. Load raw GPR files and sample mapping metadata
    message("Step 1: Loading peptide microarray data...")
    pSet <- makePeptideSet(files = NULL, path = dirToParse,
                           mapping.file = mapFile, log=TRUE)
    
    pSetNoCtrl <- makePeptideSet(files = NULL, path = dirToParse,
                           mapping.file = mapFile, log = TRUE,
                           rm.control.list = c("JPT-control", "Ig", "Cy3"),
                           empty.control.list= c("empty", "blank control"))
    
    # Save raw peptide sets as RDS objects
    saveRDS(pSet, "pSet_raw.rds")
    saveRDS(pSetNoCtrl, "pSet_no_control.rds")
    
    # 2. Visualize spatial slide artifacts and residuals
    message("Step 2: Generating array diagnostic plots...")
    pdf("array_diagnostics.pdf", width = 8, height = 6)
    tryCatch({
      plotArrayImage(pSet, array.index = 1)
    }, error = function(e) {
      warning("Failed to plot array image: ", e\$message)
    })
    
    tryCatch({
      plotArrayResiduals(pSet, array.index = 1, smooth = TRUE)
    }, error = function(e) {
      warning("Failed to plot array residuals: ", e\$message)
    })
    dev.off()
    
    # 3. Create a custom peptide coordinate database
    message("Step 3: Creating custom peptide database...")
    peps <- read.csv(pepInfoFile)
    pep_custom <- create_db(peps)
    
    # 4. Summarize replicate spots and annotate peptide positions
    message("Step 4: Summarizing peptides...")
    psSet <- summarizePeptides(pSet, summary = "mean", position = pep_custom)
    
    # 5. Normalize array intensities to correct for non-specific binding
    message("Step 5: Normalizing array intensities...")
    pnSet <- normalizeArray(psSet)
    saveRDS(pnSet, "normalized_peptide_set.rds")
    
    # 6. Smooth intensities across overlapping peptides
    message("Step 6: Smoothing intensities using sliding mean...")
    psmSet <- slidingMean(pnSet, width = 9)
    psmSetAg <- slidingMean(pnSet, width = 9, split.by.clade = FALSE)
    
    # 7. Make positivity calls comparing Pre and Post conditions
    message("Step 7: Making positivity calls...")
    calls <- makeCalls(psmSet, freq = TRUE, group = "treatment",
                         cutoff = .1, method = "FDR", verbose = TRUE)
    callsAg <- makeCalls(psmSetAg, freq = TRUE, group = "treatment",
                         cutoff = .1, method = "FDR")
    
    # Save calls objects
    saveRDS(calls, "calls_clade.rds")
    saveRDS(callsAg, "calls_aggregate.rds")
    
    # 8. Generate a tabular summary of results
    message("Step 8: Generating tabular summaries...")
    summary <- restab(psmSet, calls)
    summaryAg <- restab(psmSetAg, callsAg)
    
    # Write summaries to CSV files
    write.csv(summary, "summary_clade.csv", row.names = TRUE)
    write.csv(summaryAg, "summary_aggregate.csv", row.names = TRUE)
    
    # 9. Visualize binding peaks and clade-specific responses
    message("Step 9: Generating visualization plots...")
    pdf("analysis_plots.pdf", width = 10, height = 8)
    
    tryCatch({
      plot_inter(summaryAg)
    }, error = function(e) {
      warning("Failed to plot inter-group comparison: ", e\$message)
    })
    
    tryCatch({
      # Attempt the documented call first
      plot_clade(summary, clade=c("A", "M", "CRF01"), from = 300, to = 520)
    }, error = function(e) {
      warning("Failed to plot clade-specific responses with default clades: ", e\$message)
      # Fallback attempt using clades actually present in the user's dataset
      tryCatch({
        available_clades <- unique(summary\$clade)
        if (length(available_clades) > 0) {
          fallback_clades <- head(available_clades, 3)
          message("Attempting fallback plot with available clades: ", paste(fallback_clades, collapse = ", "))
          plot_clade(summary, clade = fallback_clades, from = 300, to = 520)
        }
      }, error = function(e2) {
        warning("Fallback clade plot also failed: ", e2\$message)
      })
    })
    
    dev.off()
    
    message("Pipeline completed successfully! Outputs written to working directory.")

    writeLines(c(
        '"BIOC_PEPSTAT_PEPTIDE_MICROARRAY_PIPELINE":',
        paste0('    pepStat: ', as.character(packageVersion('pepStat')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_peptide_microarray_pipeline.csv versions.yml
    """
}

workflow BIOC_PEPSTAT_PEPTIDE_MICROARRAY_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gpr_samples/, mapping.csv, pep_info.csv ] ]

    main:
    BIOC_PEPSTAT_PEPTIDE_MICROARRAY_PIPELINE(ch_input)

    emit:
    tables   = BIOC_PEPSTAT_PEPTIDE_MICROARRAY_PIPELINE.out.tables
    plots    = BIOC_PEPSTAT_PEPTIDE_MICROARRAY_PIPELINE.out.plots
    objects  = BIOC_PEPSTAT_PEPTIDE_MICROARRAY_PIPELINE.out.objects
    versions = BIOC_PEPSTAT_PEPTIDE_MICROARRAY_PIPELINE.out.versions
}
