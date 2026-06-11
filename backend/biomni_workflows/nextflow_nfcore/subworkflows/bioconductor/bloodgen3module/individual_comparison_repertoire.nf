#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BloodGen3Module — individual_comparison_repertoire
// Perform individual-level modular transcriptional comparison against a reference group and visualize the fingerprint heatmap.
// Input: counts.csv, coldata.csv
// Container: 1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BloodGen3Module, SummarizedExperiment
// Visualizations: heatmap
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BLOODGEN3MODULE_INDIVIDUAL_COMPARISON_REPERTOIRE {
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
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    library(BloodGen3Module)
    
    # --- Load and validate inputs ---
    message("Loading input files...")
    if (!file.exists("counts.csv") || !file.exists("coldata.csv")) {
      stop("Required input files 'counts.csv' and/or 'coldata.csv' are missing.")
    }
    
    counts <- read.csv("counts.csv", row.names = 1, check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    if (!"sample" %in% colnames(coldata) || !"condition" %in% colnames(coldata)) {
      stop("coldata.csv must contain 'sample' and 'condition' columns.")
    }
    rownames(coldata) <- coldata\$sample
    
    # Align samples between expression matrix and metadata
    common_samples <- intersect(colnames(counts), rownames(coldata))
    if (length(common_samples) == 0) {
      stop("No common samples found between counts.csv and coldata.csv")
    }
    counts <- counts[, common_samples, drop = FALSE]
    coldata <- coldata[common_samples, drop = FALSE]
    
    # Determine comparison groups dynamically
    groups <- unique(coldata\$condition)
    if (length(groups) < 2) {
      stop("At least two groups in the 'condition' column are required for comparison.")
    }
    ref_group <- if ("Control" %in% groups) "Control" else if ("control" %in% groups) "control" else groups[1]
    
    message("Reference group: ", ref_group)
    
    # Create SummarizedExperiment object
    se <- SummarizedExperiment(
      assays = list(counts = as.matrix(counts)),
      colData = coldata
    )
    
    # --- Run Individual Comparison Analysis ---
    message("Running individual comparison...")
    Individual_df <- tryCatch({
      Individualcomparison(
        se,
        sample_info = NULL,
        FC = 1.5,
        DIFF = 10,
        Group_column = "condition",
        Ref_group = ref_group,
        SummarizedExperiment = TRUE
      )
    }, error = function(e) {
      message("Individual comparison failed: ", e\$message)
      NULL
    })
    
    # --- Save results and generate visualization ---
    if (!is.null(Individual_df)) {
      write.csv(Individual_df, "individual_comparison_results.csv", row.names = TRUE)
      
      message("Generating fingerprint heatmap plot...")
      tryCatch({
        fingerprintplot(
          Individual_df,
          sample_info = NULL,
          cutoff = 15,
          rowSplit = TRUE,
          Group_column = "condition",
          show_ref_group = FALSE,
          Ref_group = ref_group,
          Aggregate = "A28",
          filename = "fingerprint_heatmap",
          height = NULL,
          width = NULL
        )
        # Handle potential file naming variations from fingerprintplot
        if (file.exists("fingerprint_heatmap")) {
          file.rename("fingerprint_heatmap", "fingerprint_heatmap.pdf")
        }
      }, error = function(e) {
        message("Error generating fingerprint plot: ", e\$message)
        pdf("fingerprint_heatmap.pdf")
        plot.new()
        text(0.5, 0.5, "Error generating fingerprint plot")
        dev.off()
      })
    } else {
      # Fallback outputs in case of failure
      write.csv(data.frame(Error = "Analysis failed"), "individual_comparison_results.csv")
      pdf("fingerprint_heatmap.pdf")
      plot.new()
      text(0.5, 0.5, "Analysis failed")
      dev.off()
    }

    writeLines(c(
        '"BIOC_BLOODGEN3MODULE_INDIVIDUAL_COMPARISON_REPERTOIRE":',
        paste0('    BloodGen3Module: ', as.character(packageVersion('BloodGen3Module')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_individual_comparison_repertoire.csv versions.yml
    """
}

workflow BIOC_BLOODGEN3MODULE_INDIVIDUAL_COMPARISON_REPERTOIRE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BLOODGEN3MODULE_INDIVIDUAL_COMPARISON_REPERTOIRE(ch_input)

    emit:
    tables   = BIOC_BLOODGEN3MODULE_INDIVIDUAL_COMPARISON_REPERTOIRE.out.tables
    plots    = BIOC_BLOODGEN3MODULE_INDIVIDUAL_COMPARISON_REPERTOIRE.out.plots
    objects  = BIOC_BLOODGEN3MODULE_INDIVIDUAL_COMPARISON_REPERTOIRE.out.objects
    versions = BIOC_BLOODGEN3MODULE_INDIVIDUAL_COMPARISON_REPERTOIRE.out.versions
}
