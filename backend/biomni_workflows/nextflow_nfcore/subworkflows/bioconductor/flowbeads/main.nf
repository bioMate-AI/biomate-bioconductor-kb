#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowBeads — absolute_mef_normalization
// Load bead data, gate bead populations, compute absolute MEF transformation parameters, and apply the transform to sample flow cytometry data.
// Input: beads1.fcs, dakomef.csv, flow.data
// Container: quay.io/biocontainers/bioconductor-flowbeads:1.44.0--r44hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: flowBeads, flowCore
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load bead data and MEF configuration using BeadFlowFrame
//  * 2. [Core Analysis] Gate bead populations using gateBeads
//  * 3. [Core Analysis] Extract MEF transform parameters using getMEFtransform
//  * 4. [Core Analysis] Apply MEF transform to sample data using toMEF
//  * 5. [Visualization & Output] Generate QC report using generateReport

nextflow.enable.dsl = 2

process BIOC_FLOWBEADS_ABSOLUTE_MEF_NORMALIZATION {
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
    .bm_deps <- c("flowBeads", "flowCore")
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
    library(flowBeads)
    library(flowCore)
    
    # Define input file paths (must exist in the working directory)
    fcs_day1 <- "beads1.fcs"
    bead_config <- "dakomef.csv"
    flow_data_file <- "flow.data"
    
    # 1. Load bead data using BeadFlowFrame
    beads1 <- BeadFlowFrame(fcs.filename=fcs_day1,
                            bead.filename=bead_config)
    
    # Load the sample flow cytometry data
    flow.data <- tryCatch({
      read.FCS(flow_data_file)
    }, error = function(e) {
      readRDS(flow_data_file)
    })
    
    # 2. Gate bead populations using gateBeads
    gbeads1 <- gateBeads(beads1)
    
    # 3. Compute absolute MEF normalization transforms using getMEFtransform
    mef.transforms <- getMEFtransform(gbeads1)
    
    # 4. Apply the MEF transform to the sample data
    normalized_flow_data <- toMEF(gbeads1, flow.data)
    
    # Extract the MEF transform function to align MFIs
    fun <- mef.transforms\$APC\$fun
    beads1.mean.fi.APC <- getClusteringStats(gbeads1)['mean.fi','APC',]
    raw_mef1 <- fun(beads1.mean.fi.APC)
    
    mfi1 <- getTransformFunction(gbeads1)(beads1.mean.fi.APC)
    fun.mfi1 <- getTransformFunction(gbeads1)(raw_mef1)
    
    # Save the MEF transforms object
    saveRDS(mef.transforms, file = "mef_transforms.rds")
    
    # Save the normalized flow data
    write.FCS(normalized_flow_data, filename = "normalized_flow_data.fcs")
    
    # Save the MFI alignment results to a CSV file
    mfi_alignment_df <- data.frame(
      Bead_Population = seq_along(mfi1),
      MFI1_Transformed = mfi1,
      MEF1_Transformed = fun.mfi1
    )
    write.csv(mfi_alignment_df, file = "mfi_alignment_results.csv", row.names = FALSE)
    
    # Generate diagnostic plots showing the alignment
    pdf("absolute_mef_normalization_alignment.pdf", width = 10, height = 5)
    old.par <- par(no.readonly = TRUE)
    par(mfrow = c(1, 2))
    
    # Plot before MEF normalization
    plot(mfi1,
         mfi1,
         xlim = c(0, 5),
         ylim = c(0, 5),
         xlab = 'APC MFI Beads Day 1',
         ylab = 'APC MFI Beads Day 1',
         main = 'Before MEF Normalization',
         col = 'blue',
         pch = 19)
    abline(b = 1, a = 0, lty = 2, col = 'red')
    
    # Plot after MEF normalization
    plot(mfi1,
         fun.mfi1,
         xlim = c(0, 5),
         ylim = c(0, 5),
         xlab = 'APC MFI Beads Day 1',
         ylab = 'APC MEF Beads Day 1',
         main = 'After MEF Normalization',
         col = 'blue',
         pch = 19)
    abline(b = 1, a = 0, lty = 2, col = 'red')
    
    par(old.par)
    dev.off()
    
    # Optional: Generate HTML quality control reports if supported by the environment
    tryCatch({
      generateReport(gbeads1, output.file = 'report_day1.html')
    }, error = function(e) {
      warning("Could not generate HTML reports: ", e\$message)
    })

    writeLines(c(
        '"BIOC_FLOWBEADS_ABSOLUTE_MEF_NORMALIZATION":',
        paste0('    flowBeads: ', as.character(packageVersion('flowBeads')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_absolute_mef_normalization.csv versions.yml
    """
}

workflow BIOC_FLOWBEADS_ABSOLUTE_MEF_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ beads1.fcs, dakomef.csv, flow.data ] ]

    main:
    BIOC_FLOWBEADS_ABSOLUTE_MEF_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_FLOWBEADS_ABSOLUTE_MEF_NORMALIZATION.out.tables
    plots    = BIOC_FLOWBEADS_ABSOLUTE_MEF_NORMALIZATION.out.plots
    objects  = BIOC_FLOWBEADS_ABSOLUTE_MEF_NORMALIZATION.out.objects
    versions = BIOC_FLOWBEADS_ABSOLUTE_MEF_NORMALIZATION.out.versions
}
