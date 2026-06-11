#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: vulcan — vulcan_pipeline
// Run the full VULCAN pipeline to identify co-regulatory factors from ChIP-Seq data and a regulatory network.
// Input: vfile.csv, network.rda
// Container: quay.io/biocontainers/bioconductor-vulcan:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: vulcan
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import ChIP-Seq data using vulcan.import
//  * 2. [Core Analysis] Annotate peaks to gene names using vulcan.annotate
//  * 3. [Core Analysis] Normalize peak abundance using vulcan.normalize
//  * 4. [Core Analysis] Run VULCAN analysis using vulcan
//  * 5. [Visualization & Output] Plot master regulators using plot

nextflow.enable.dsl = 2

process BIOC_VULCAN_VULCAN_PIPELINE {
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
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("vulcan")
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
    library(vulcan)
    
    # Validate input files
    if (!file.exists("vfile.csv")) {
      stop("Error: Input annotation file 'vfile.csv' not found in the working directory.")
    }
    if (!file.exists("network.rda")) {
      stop("Error: Input network file 'network.rda' not found in the working directory.")
    }
    
    # 1. Import ChIP-Seq data
    message("Importing ChIP-Seq data from vfile.csv...")
    vobj <- vulcan.import("vfile.csv")
    
    # 2. Annotate peaks to gene names
    message("Annotating peaks...")
    vobj <- vulcan.annotate(vobj, lborder=-10000, rborder=10000, method="sum")
    
    # 3. Normalize peak abundance
    message("Normalizing peak abundance...")
    vobj <- vulcan.normalize(vobj)
    print(names(vobj\$samples))
    
    # 4. Load the gene regulatory network
    message("Loading gene regulatory network...")
    load("network.rda")
    
    # Ensure 'network' object exists in the loaded environment
    if (!exists("network")) {
      stop("Error: 'network' object not found in network.rda")
    }
    
    # 5. Run VULCAN analysis
    message("Running VULCAN analysis...")
    conditions <- names(vobj\$samples)
    if (length(conditions) < 2) {
      stop("Error: At least two conditions are required for contrast.")
    }
    vobj_analysis <- vulcan(vobj, network=network, contrast=conditions[1:2], minsize=5)
    
    # 6. Plot master regulators and save to PDF
    message("Generating master regulator plot...")
    pdf("msviper_plot.pdf", width=8, height=6)
    plot(vobj_analysis\$msviper, mrs=7)
    dev.off()
    
    # 7. Save outputs
    message("Saving output files...")
    saveRDS(vobj_analysis, "vobj_analysis.rds")
    
    # Export msviper summary to CSV
    tryCatch({
      msviper_summary <- summary(vobj_analysis\$msviper)
      write.csv(msviper_summary, "msviper_summary.csv", row.names=TRUE)
      message("Saved msviper summary to 'msviper_summary.csv'")
    }, error = function(e) {
      warning("Could not write msviper summary to CSV: ", e\$message)
    })
    
    # Export normalized counts to CSV
    tryCatch({
      if (!is.null(vobj\$normalized)) {
        write.csv(vobj\$normalized, "normalized_counts.csv", row.names=TRUE)
        message("Saved normalized counts to 'normalized_counts.csv'")
      }
    }, error = function(e) {
      warning("Could not write normalized counts to CSV: ", e\$message)
    })
    
    message("VULCAN pipeline completed successfully!")

    writeLines(c(
        '"BIOC_VULCAN_VULCAN_PIPELINE":',
        paste0('    vulcan: ', as.character(packageVersion('vulcan')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_vulcan_pipeline.csv versions.yml
    """
}

workflow BIOC_VULCAN_VULCAN_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ vfile.csv, network.rda ] ]

    main:
    BIOC_VULCAN_VULCAN_PIPELINE(ch_input)

    emit:
    tables   = BIOC_VULCAN_VULCAN_PIPELINE.out.tables
    plots    = BIOC_VULCAN_VULCAN_PIPELINE.out.plots
    objects  = BIOC_VULCAN_VULCAN_PIPELINE.out.objects
    versions = BIOC_VULCAN_VULCAN_PIPELINE.out.versions
}
