#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: HMMcopy — matched_tumor_normal_correction
// Normalize tumor copy number profiles by matched normal copy number profiles to eliminate germline copy number variations and reduce noise, followed by segmentat
// Input: tumour.wig, normal.wig, gc.wig, map.wig
// Container: quay.io/biocontainers/bioconductor-hmmcopy:1.52.0--r45h01b2380_0
// R packages: HMMcopy
// Bioconductor: 3.20 | R: 4.4
// Requires: HMMcopy
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and correct normal sample read counts using wigsToRangedData and correctReadcount
//  * 2. [Input & Preparation] Load and correct tumor sample read counts using wigsToRangedData and correctReadcount
//  * 3. [Core Analysis] Subtract normal copy number from tumor copy number in log2 space to obtain somatic copy number
//  * 4. [Core Analysis] Segment the somatic copy number profile using HMMsegment
//  * 5. [Visualization & Output] Plot the somatic segments using plotSegments

nextflow.enable.dsl = 2

process BIOC_HMMCOPY_MATCHED_TUMOR_NORMAL_CORRECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("HMMcopy")
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
    
    # Set options
    options(stringsAsFactors = TRUE)
    
    # Load required library
    library(HMMcopy)
    
    # Define input files in the working directory
    rfile <- "normal.wig"
    gfile <- "gc.wig"
    mfile <- "map.wig"
    tfile <- "tumour.wig"
    
    # Verify that all required input files exist
    required_files <- c(rfile, gfile, mfile, tfile)
    missing_files <- required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      stop(paste("Error: Missing required input files in the working directory:", 
                 paste(missing_files, collapse = ", ")))
    }
    
    # 1. Load and correct normal sample read counts
    normal_reads <- wigsToRangedData(rfile, gfile, mfile)
    normal_copy <- correctReadcount(normal_reads)
    
    # 2. Load and correct tumor sample read counts
    tumour_copy <- correctReadcount(wigsToRangedData(tfile, gfile, mfile))
    
    # 3. Subtract normal copy number from tumor copy number in log2 space to obtain somatic copy number
    somatic_copy <- tumour_copy
    somatic_copy\$copy <- tumour_copy\$copy - normal_copy\$copy
    
    # 4. Segment the somatic copy number profile using HMMsegment
    # Retrieve default parameters
    default_param <- HMMsegment(tumour_copy, getparam = TRUE)
    
    # Adjust parameters to reduce oversegmentation and set custom state ranges
    longseg_param <- default_param
    longseg_param\$e <- 0.999999999999999
    longseg_param\$strength <- 1e30
    newmu_param <- longseg_param
    newmu_param\$mu <- c(-0.5, -0.4, -0.15, 0.1, 0.4, 0.7)
    newmu_param\$m <- newmu_param\$mu
    
    # Run segmentation on the somatic copy number profile
    somatic_segments <- HMMsegment(somatic_copy, newmu_param, verbose = FALSE)
    
    # 5. Plot the somatic segments and save to a PDF file
    pdf("somatic_segments.pdf", width = 10, height = 6)
    par(cex.main = 0.5, cex.lab = 0.5, cex.axis = 0.5, mar = c(2, 1.5, 0, 0), mgp = c(1, 0.5, 0))
    plotSegments(somatic_copy, somatic_segments, pch = ".",
      ylab = "Tumour Copy Number", xlab = "Chromosome Position")
    dev.off()
    
    # Save meaningful results to output files
    saveRDS(somatic_copy, "somatic_copy.rds")
    saveRDS(somatic_segments, "somatic_segments.rds")
    
    # Export somatic copy number profile as a CSV table
    tryCatch({
      write.csv(as.data.frame(somatic_copy), "somatic_copy.csv", row.names = FALSE)
    }, error = function(e) {
      warning("Could not write somatic_copy to CSV: ", e\$message)
    })
    
    # Export segment details as a CSV table
    tryCatch({
      if (!is.null(somatic_segments\$segs)) {
        write.csv(somatic_segments\$segs, "somatic_segments.csv", row.names = FALSE)
      }
    }, error = function(e) {
      warning("Could not write somatic_segments table to CSV: ", e\$message)
    })

    writeLines(c(
        '"BIOC_HMMCOPY_MATCHED_TUMOR_NORMAL_CORRECTION":',
        paste0('    HMMcopy: ', as.character(packageVersion('HMMcopy')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matched_tumor_normal_correction.csv versions.yml
    """
}

workflow BIOC_HMMCOPY_MATCHED_TUMOR_NORMAL_CORRECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ tumour.wig, normal.wig, gc.wig, map.wig ] ]

    main:
    BIOC_HMMCOPY_MATCHED_TUMOR_NORMAL_CORRECTION(ch_input)

    emit:
    tables   = BIOC_HMMCOPY_MATCHED_TUMOR_NORMAL_CORRECTION.out.tables
    plots    = BIOC_HMMCOPY_MATCHED_TUMOR_NORMAL_CORRECTION.out.plots
    objects  = BIOC_HMMCOPY_MATCHED_TUMOR_NORMAL_CORRECTION.out.objects
    versions = BIOC_HMMCOPY_MATCHED_TUMOR_NORMAL_CORRECTION.out.versions
}
