#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CNVrd2 — polymorphic_region_detection
// Identify copy number polymorphic regions and define their genomic boundaries.
// Input: objectCNVrd2, resultSegment
// Container: quay.io/biocontainers/bioconductor-cnvrd2:1.48.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CNVrd2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify polymorphic regions using identifyPolymorphicRegion
//  * 2. [Visualization & Output] Plot polymorphic regions and define boundaries using plotPolymorphicRegion

nextflow.enable.dsl = 2

process BIOC_CNVRD2_POLYMORPHIC_REGION_DETECTION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
        library(CNVrd2)
        
        # Define input file paths
        object_file <- "objectCNVrd2.rds"
        segment_file <- "resultSegment.rds"
        
        # Check for existence of user input files
        if (!file.exists(object_file)) {
          stop(paste("Required input file missing:", object_file))
        }
        if (!file.exists(segment_file)) {
          stop(paste("Required input file missing:", segment_file))
        }
        
        # Read user input files
        objectCNVrd2 <- readRDS(object_file)
        resultSegment <- readRDS(segment_file)
        
        # Stage 1: Identify polymorphic regions
        fcgr3PolymorphicRegion <- identifyPolymorphicRegion(Object = objectCNVrd2,
                                                            segmentObject = resultSegment, 
                                                            plotLegend = FALSE)
        
        # Save the identified polymorphic region object
        saveRDS(fcgr3PolymorphicRegion, "fcgr3PolymorphicRegion.rds")
        
        # Stage 2: Plot polymorphic regions and define boundaries
        # Open PDF device to capture the plots
        pdf("polymorphic_regions_plots.pdf", width = 8, height = 6)
        
        # Plot 1: Default thresholds
        ranges_default <- plotPolymorphicRegion(Object = objectCNVrd2, 
                                                polymorphicRegionObject = fcgr3PolymorphicRegion,
                                                xlim = c(objectCNVrd2@st, objectCNVrd2@en), 
                                                drawThresholds = TRUE,
                                                typePlot = "SD")
        
        # Plot 2: Custom SD threshold (0.05)
        ranges_sd05 <- plotPolymorphicRegion(Object = objectCNVrd2, 
                                             polymorphicRegionObject = fcgr3PolymorphicRegion,
                                             xlim = c(objectCNVrd2@st, objectCNVrd2@en), 
                                             sdThreshold = 0.05, 
                                             drawThresholds = TRUE,
                                             typePlot = "SD")
        
        # Close the PDF device
        dev.off()
        
        # Save the defined genomic boundaries (IRanges objects)
        saveRDS(ranges_default, "polymorphic_ranges_default.rds")
        write.csv(as.data.frame(ranges_default), "polymorphic_ranges_default.csv", row.names = FALSE)
        
        saveRDS(ranges_sd05, "polymorphic_ranges_sd05.rds")
        write.csv(as.data.frame(ranges_sd05), "polymorphic_ranges_sd05.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_CNVRD2_POLYMORPHIC_REGION_DETECTION":',
        paste0('    CNVrd2: ', as.character(packageVersion('CNVrd2')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_polymorphic_region_detection.csv versions.yml
    """
}

workflow BIOC_CNVRD2_POLYMORPHIC_REGION_DETECTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ objectCNVrd2, resultSegment ] ]

    main:
    BIOC_CNVRD2_POLYMORPHIC_REGION_DETECTION(ch_input)

    emit:
    tables   = BIOC_CNVRD2_POLYMORPHIC_REGION_DETECTION.out.tables
    plots    = BIOC_CNVRD2_POLYMORPHIC_REGION_DETECTION.out.plots
    objects  = BIOC_CNVRD2_POLYMORPHIC_REGION_DETECTION.out.objects
    versions = BIOC_CNVRD2_POLYMORPHIC_REGION_DETECTION.out.versions
}
