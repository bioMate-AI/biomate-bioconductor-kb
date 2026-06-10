#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: similaRpeak — metric_factory_similarity
// Calculate specific individual similarity metrics using a reusable MetricFactory object.
// Input: profile1, profile2
// Container: quay.io/biocontainers/bioconductor-similarpeak:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: similaRpeak
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize a MetricFactory object with specific thresholds
//  * 2. [Core Analysis] Calculate individual metrics using the factory's createMetric method

nextflow.enable.dsl = 2

process BIOC_SIMILARPEAK_METRIC_FACTORY_SIMILARITY {
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
    
    # Load required library
    library(similaRpeak)
    
    # Helper function to read profiles robustly
    read_profile <- function(filename) {
      if (file.exists(filename)) {
        # Try reading as RDS first
        val <- tryCatch({
          readRDS(filename)
        }, error = function(e) NULL)
        if (is.numeric(val)) return(val)
        
        # Try reading as scan
        val <- tryCatch({
          scan(filename, quiet = TRUE)
        }, error = function(e) NULL)
        if (is.numeric(val) && length(val) > 0) return(val)
      }
      
      # Try with .rds extension
      if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      }
      
      # Try with .txt extension
      if (file.exists(paste0(filename, ".txt"))) {
        return(scan(paste0(filename, ".txt"), quiet = TRUE))
      }
      
      stop(paste("Error: Could not read input file", filename))
    }
    
    # Read user inputs
    profile1 <- read_profile("profile1")
    profile2 <- read_profile("profile2")
    
    # Validate inputs
    if (length(profile1) != length(profile2)) {
      stop("Error: profile1 and profile2 must have the exact same length.")
    }
    if (any(profile1 < 0) || any(profile2 < 0)) {
      stop("Error: Profiles must not contain negative values.")
    }
    
    # 1. Initialize a MetricFactory object with specific thresholds
    factory = MetricFactory\$new(diffPosMaxTolerance=0.04)
    
    # 2. Calculate individual metrics using the factory's createMetric method
    ratio_max_max <- factory\$createMetric(metricType="RATIO_MAX_MAX", 
                            profile1=profile1, 
                            profile2=profile2)
    
    ratio_normalized_intersect <- factory\$createMetric(
                            metricType="RATIO_NORMALIZED_INTERSECT",
                            profile1=profile1, 
                            profile2=profile2)
    
    # Save results to RDS
    results <- list(
      ratio_max_max = ratio_max_max,
      ratio_normalized_intersect = ratio_normalized_intersect
    )
    saveRDS(results, "similarity_metrics.rds")
    
    # Save results to CSV
    metrics_df <- data.frame(
      Metric = c("RATIO_MAX_MAX", "RATIO_NORMALIZED_INTERSECT"),
      Value = c(
        ifelse(is.null(ratio_max_max), NA, as.numeric(ratio_max_max[[1]])),
        ifelse(is.null(ratio_normalized_intersect), NA, as.numeric(ratio_normalized_intersect[[1]]))
      )
    )
    write.csv(metrics_df, "similarity_metrics.csv", row.names = FALSE)
    
    # Generate PDF plot comparing the profiles
    pdf("profile_comparison.pdf", width = 8, height = 6)
    plot(profile1, type = "l", col = "blue", xlab = "Position", ylab = "Coverage", 
         main = "ChIP-Seq Profile Comparison")
    lines(profile2, col = "darkgreen")
    legend("topright", legend = c("Profile 1", "Profile 2"), col = c("blue", "darkgreen"), lty = 1)
    dev.off()

    writeLines(c(
        '"BIOC_SIMILARPEAK_METRIC_FACTORY_SIMILARITY":',
        paste0('    similaRpeak: ', as.character(packageVersion('similaRpeak')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metric_factory_similarity.csv versions.yml
    """
}

workflow BIOC_SIMILARPEAK_METRIC_FACTORY_SIMILARITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ profile1, profile2 ] ]

    main:
    BIOC_SIMILARPEAK_METRIC_FACTORY_SIMILARITY(ch_input)

    emit:
    tables   = BIOC_SIMILARPEAK_METRIC_FACTORY_SIMILARITY.out.tables
    plots    = BIOC_SIMILARPEAK_METRIC_FACTORY_SIMILARITY.out.plots
    objects  = BIOC_SIMILARPEAK_METRIC_FACTORY_SIMILARITY.out.objects
    versions = BIOC_SIMILARPEAK_METRIC_FACTORY_SIMILARITY.out.versions
}
