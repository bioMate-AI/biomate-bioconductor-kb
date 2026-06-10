#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: scatterHatch — textured_scatterplot
// Create and customize a scatterplot where groups are distinguished by both color and textured hatching patterns.
// Input: pdacData.csv
// Container: quay.io/biocontainers/bioconductor-scatterhatch:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, scatterHatch
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load the package and prepare the coordinate data with group annotations. 2. Generate a basic scatterHatch plot using default patte

nextflow.enable.dsl = 2

process BIOC_SCATTERHATCH_TEXTURED_SCATTERPLOT {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(scatterHatch)
    library(ggplot2)
    
    # 1. Load the package and prepare the coordinate data with group annotations
    # Read the user input file from the working directory
    if (!file.exists("pdacData.csv")) {
      stop("Required input file 'pdacData.csv' not found in the working directory.")
    }
    
    pdacData <- read.csv("pdacData.csv")
    
    # Process the data as in the documented vignette
    pdacData\$cellID <- paste0('cell_', 1:nrow(pdacData))
    pdacData\$Yt <- -pdacData\$Yt
    
    pancreas_frames = c(1:6, 27:31, 15:19, 40:44)
    PDAC_frames = c(23:26, 35:37, 51:52, 64:65, 77)
    small_intestines_frames = c(49:50, 63, 75:76, 88:89, 100:103, 112:116, 125:129, 137:140)
    
    annotateLocation <- function(frame){
        if (frame %in% pancreas_frames){return("Pancreas")}
        if (frame %in% PDAC_frames){return("PDAC")}
        if (frame %in% small_intestines_frames){return("Small Intestine")}
        return("Other")
    }
    pdacData\$location <- sapply(pdacData\$frame, annotateLocation)
    
    # Save the annotated dataset
    write.csv(pdacData, "pdacData_annotated.csv", row.names = FALSE)
    
    # 2. Generate a basic scatterHatch plot using default patterns
    plt_basic <- scatterHatch(data = pdacData, x = "Xt", y = "Yt", 
        color_by = "location", legendTitle = "Tissue Type")
    
    # Save the basic plot to a PDF file
    pdf("scatterHatch_basic.pdf", width = 11, height = 8)
    plot(plt_basic)
    dev.off()
    
    # 3. Define custom pattern aesthetics (angles, line widths, and types) in a list
    patternList = list(
        list(pattern="/", angle = 70), 
        list(pattern="-"), 
        list(pattern="x", angle = c(135, 90, 45), lineWidth = 0.2), 
        list(pattern="+")
    )
    
    # 4. Generate and render the customized scatterHatch plot
    plt_custom <- scatterHatch(data = pdacData, x = "Xt", y = "Yt", 
        color_by = "location", legendTitle = "Tissue Type", 
        patternList = patternList)
    
    # Save the customized plot to a PDF file
    pdf("scatterHatch_custom.pdf", width = 11, height = 8)
    plot(plt_custom)
    dev.off()
    
    # Save the plot objects as RDS for downstream use
    saveRDS(plt_basic, "scatterHatch_basic.rds")
    saveRDS(plt_custom, "scatterHatch_custom.rds")
    
    message("Pipeline completed successfully. Outputs saved: pdacData_annotated.csv, scatterHatch_basic.pdf, scatterHatch_custom.pdf, scatterHatch_basic.rds, scatterHatch_custom.rds")

    writeLines(c(
        '"BIOC_SCATTERHATCH_TEXTURED_SCATTERPLOT":',
        paste0('    scatterHatch: ', as.character(packageVersion('scatterHatch')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_textured_scatterplot.csv versions.yml
    """
}

workflow BIOC_SCATTERHATCH_TEXTURED_SCATTERPLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pdacData.csv ] ]

    main:
    BIOC_SCATTERHATCH_TEXTURED_SCATTERPLOT(ch_input)

    emit:
    tables   = BIOC_SCATTERHATCH_TEXTURED_SCATTERPLOT.out.tables
    plots    = BIOC_SCATTERHATCH_TEXTURED_SCATTERPLOT.out.plots
    objects  = BIOC_SCATTERHATCH_TEXTURED_SCATTERPLOT.out.objects
    versions = BIOC_SCATTERHATCH_TEXTURED_SCATTERPLOT.out.versions
}
