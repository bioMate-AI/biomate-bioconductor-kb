#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: twoddpcr — custom_classification_integration
// Integrate a custom classification method into the ddpcrPlate object and ensure the classes are correctly formatted.
// Input: data/amplitudes
// Container: quay.io/biocontainers/bioconductor-twoddpcr:1.34.0--r45hdfd78af_0
// Requires: ggplot2, twoddpcr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the plate and extract raw droplet amplitudes. 2. Apply a custom classification function to the droplet data. 3. Relabel the c

nextflow.enable.dsl = 2

process BIOC_TWODDPCR_CUSTOM_CLASSIFICATION_INTEGRATION {
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
    .bm_deps <- c("ggplot2", "twoddpcr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
    library(twoddpcr)
    library(ggplot2)
    
    # Ensure input directory exists
    if (!dir.exists("data/amplitudes")) {
      stop("Error: Input directory 'data/amplitudes' does not exist. Please ensure raw amplitude CSV files are placed there.")
    }
    
    # Create output directory if it doesn't exist
    if (!dir.exists("output")) {
      dir.create("output", recursive = TRUE)
    }
    
    # 1. Load the plate and extract raw droplet amplitudes
    plate <- ddpcrPlate(well="data/amplitudes")
    
    allDrops <- amplitudes(plate)
    # Assign the list of data frames to a variable named 'amplitudes' 
    # so that the exact documented call `do.call(rbind, amplitudes)` works correctly.
    amplitudes <- allDrops
    allDrops <- do.call(rbind, amplitudes)
    
    # 2. Apply a custom classification function to the droplet data
    someClassificationMethod <- function(df) {
      # Simple threshold-based classification for demonstration
      # We use the median of Ch1 and Ch2 amplitudes as thresholds
      ch1_thresh <- median(df\$Ch1.Amplitude)
      ch2_thresh <- median(df\$Ch2.Amplitude)
      
      classes <- rep("NN", nrow(df))
      classes[df\$Ch1.Amplitude >= ch1_thresh & df\$Ch2.Amplitude < ch2_thresh] <- "PN"
      classes[df\$Ch1.Amplitude < ch1_thresh & df\$Ch2.Amplitude >= ch2_thresh] <- "NP"
      classes[df\$Ch1.Amplitude >= ch1_thresh & df\$Ch2.Amplitude >= ch2_thresh] <- "PP"
      
      return(factor(classes, levels=c("NN", "NP", "PN", "PP", "Rain", "N/A")))
    }
    
    allDrops\$class <- someClassificationMethod(allDrops)
    
    # 3. Relabel the custom classes to match the package's expected factor levels
    allDrops <- relabelClasses(allDrops, classCol="class")
    
    # 4. Assign the custom classification back to the ddpcrPlate object
    plateClassification(plate, cMethod="nameOfCMethod") <- allDrops\$class
    
    # --- Save Outputs ---
    
    # Save the classification summary table
    summary_df <- plateSummary(plate, cMethod="nameOfCMethod")
    write.csv(summary_df, "output/plate_summary.csv", row.names = TRUE)
    
    # Save the classification plot
    pdf("output/custom_classification_plot.pdf", width = 7, height = 6)
    print(dropletPlot(plate, cMethod="nameOfCMethod"))
    dev.off()
    
    # Save the classified plate object
    saveRDS(plate, "output/classified_plate.rds")

    writeLines(c(
        '"BIOC_TWODDPCR_CUSTOM_CLASSIFICATION_INTEGRATION":',
        paste0('    twoddpcr: ', as.character(packageVersion('twoddpcr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_classification_integration.csv versions.yml
    """
}

workflow BIOC_TWODDPCR_CUSTOM_CLASSIFICATION_INTEGRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ data/amplitudes ] ]

    main:
    BIOC_TWODDPCR_CUSTOM_CLASSIFICATION_INTEGRATION(ch_input)

    emit:
    tables   = BIOC_TWODDPCR_CUSTOM_CLASSIFICATION_INTEGRATION.out.tables
    plots    = BIOC_TWODDPCR_CUSTOM_CLASSIFICATION_INTEGRATION.out.plots
    objects  = BIOC_TWODDPCR_CUSTOM_CLASSIFICATION_INTEGRATION.out.objects
    versions = BIOC_TWODDPCR_CUSTOM_CLASSIFICATION_INTEGRATION.out.versions
}
