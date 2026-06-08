#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: katdetectr — custom_cutoff_kataegis_detection
// Detect kataegis foci using a custom segment-specific IMD cutoff function instead of a fixed threshold.
// Input: genomic_variants.rds
// Container: quay.io/biocontainers/bioconductor-katdetectr:1.12.0--r45hdfd78af_0
// Requires: dplyr, katdetectr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define custom functions for modeling sample rate and calculating segment-specific IMD cutoffs
//  * 2. [Core Analysis] Run detectKataegis with the custom IMD cutoff function

nextflow.enable.dsl = 2

process BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    library(katdetectr)
    library(dplyr)
    
    # 1. Read the user input file
    if (!file.exists("genomic_variants.rds")) {
        stop("Error: genomic_variants.rds not found in the working directory.")
    }
    syntheticData <- readRDS("genomic_variants.rds")
    
    # 2. Define custom functions for modeling sample rate and calculating segment-specific IMD cutoffs
    modelSampleRate <- function(IMDs) {
        lambda <- log(2) / median(IMDs)
    
        return(lambda)
    }
    
    nthroot <- function(x, n) {
        y <- x^(1 / n)
    
        return(y)
    }
    
    IMDcutoffFun <- function(genomicVariants, segments) {
        IMDs <- genomicVariants\$IMD
        totalVariants <- segments\$totalVariants
        width <- segments |>
            dplyr::as_tibble() |>
            dplyr::pull(width)
    
        sampleRate <- modelSampleRate(IMDs)
    
        IMDcutoff <- -log(1 - nthroot(0.01 / width, ifelse(totalVariants != 0, totalVariants - 1, 1))) / sampleRate
    
        IMDcutoff <- replace(IMDcutoff, IMDcutoff > 1000, 1000)
    
        return(IMDcutoff)
    }
    
    # 3. Run detectKataegis with the custom IMD cutoff function
    kdCustom <- detectKataegis(syntheticData, IMDcutoff = IMDcutoffFun)
    
    # 4. Write named output files for the meaningful results
    # Save the full KatDetect object
    saveRDS(kdCustom, "kd_custom_results.rds")
    
    # Save genomic variants as CSV
    variants_df <- as.data.frame(getGenomicVariants(kdCustom))
    write.csv(variants_df, "custom_genomic_variants.csv", row.names = FALSE)
    
    # Save segments as CSV
    segments_df <- as.data.frame(getSegments(kdCustom))
    write.csv(segments_df, "custom_segments.csv", row.names = FALSE)
    
    # Save kataegis foci as CSV
    foci_df <- as.data.frame(getKataegisFoci(kdCustom))
    write.csv(foci_df, "custom_kataegis_foci.csv", row.names = FALSE)
    
    # Save rainfall plot as PDF
    pdf("custom_rainfall_plot.pdf", width = 12, height = 7)
    tryCatch({
        plot_obj <- rainfallPlot(kdCustom, showKataegis = TRUE, showSegmentation = TRUE)
        print(plot_obj)
    }, error = function(e) {
        warning("Could not generate rainfall plot: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION":',
        paste0('    katdetectr: ', as.character(packageVersion('katdetectr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_cutoff_kataegis_detection.csv versions.yml
    """
}

workflow BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genomic_variants.rds ] ]

    main:
    BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION(ch_input)

    emit:
    tables   = BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION.out.tables
    plots    = BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION.out.plots
    objects  = BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION.out.objects
    versions = BIOC_KATDETECTR_CUSTOM_CUTOFF_KATAEGIS_DETECTION.out.versions
}
