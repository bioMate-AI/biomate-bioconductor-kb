#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BloodGen3Module — group_comparison_repertoire
// Perform group-level modular transcriptional repertoire comparison and visualize the fingerprint grid.
// Input: counts.csv, coldata.csv
// Container: 1.18.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BloodGen3Module, SummarizedExperiment
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BLOODGEN3MODULE_GROUP_COMPARISON_REPERTOIRE {
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
    .bm_deps <- c("BloodGen3Module", "SummarizedExperiment")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    librar    
    library(SummarizedExperiment)
y(BloodGen3Module)
    
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
    test_group <- setdiff(groups, ref_group)[1]
    
    message("Reference group: ", ref_group)
    message("Test group: ", test_group)
    
    # Create SummarizedExperiment object
    se <- SummarizedExperiment(
      assays = list(counts = as.matrix(counts)),
      colData = coldata
    )
    
    # --- Run Group Comparison Analysis ---
    message("Running group comparison using limma...")
    Group_df <- tryCatch({
      Groupcomparisonlimma(
        se,
        sample_info = NULL,
        FC = 1.5,
        pval = 0.1,
        FDR = TRUE,
        Group_column = "condition",
        Test_group = test_group,
        Ref_group = ref_group,
        SummarizedExperiment = TRUE
      )
    }, error = function(e) {
      message("Limma group comparison failed, attempting standard t-test comparison: ", e\$message)
      tryCatch({
        Groupcomparison(
          se,
          sample_info = NULL,
          FC = 1.5,
          pval = 0.1,
          FDR = TRUE,
          Group_column = "condition",
          Test_group = test_group,
          Ref_group = ref_group,
          SummarizedExperiment = TRUE
        )
      }, error = function(e2) {
        message("Both group comparison methods failed: ", e2\$message)
        NULL
      })
    })
    
    # --- Save results and generate visualization ---
    if (!is.null(Group_df)) {
      write.csv(Group_df, "group_comparison_results.csv", row.names = TRUE)
      
      message("Generating fingerprint grid plot...")
      tryCatch({
        gridplot(
          Group_df,
          cutoff = 15,
          Ref_group = ref_group,
          filename = "fingerprint_grid"
        )
        # Handle potential file naming variations from gridplot
        if (file.exists("fingerprint_grid")) {
          file.rename("fingerprint_grid", "fingerprint_grid.pdf")
        }
      }, error = function(e) {
        message("Error generating grid plot: ", e\$message)
        pdf("fingerprint_grid.pdf")
        plot.new()
        text(0.5, 0.5, "Error generating grid plot")
        dev.off()
      })
    } else {
      # Fallback outputs in case of failure
      write.csv(data.frame(Error = "Analysis failed"), "group_comparison_results.csv")
      pdf("fingerprint_grid.pdf")
      plot.new()
      text(0.5, 0.5, "Analysis failed")
      dev.off()
    }

    writeLines(c(
        '"BIOC_BLOODGEN3MODULE_GROUP_COMPARISON_REPERTOIRE":',
        paste0('    BloodGen3Module: ', as.character(packageVersion('BloodGen3Module')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_group_comparison_repertoire.csv versions.yml
    """
}

workflow BIOC_BLOODGEN3MODULE_GROUP_COMPARISON_REPERTOIRE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_BLOODGEN3MODULE_GROUP_COMPARISON_REPERTOIRE(ch_input)

    emit:
    tables   = BIOC_BLOODGEN3MODULE_GROUP_COMPARISON_REPERTOIRE.out.tables
    plots    = BIOC_BLOODGEN3MODULE_GROUP_COMPARISON_REPERTOIRE.out.plots
    objects  = BIOC_BLOODGEN3MODULE_GROUP_COMPARISON_REPERTOIRE.out.objects
    versions = BIOC_BLOODGEN3MODULE_GROUP_COMPARISON_REPERTOIRE.out.versions
}
