#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RTCA — rtca_import_annotate_and_visualize
// Import raw RTCA data, annotate wells with experimental metadata, manage timeline events, and visualize cell index curves.
// Input: testOutput.csv, testOutputPhenoData.csv
// Container: quay.io/biocontainers/bioconductor-rtca:1.62.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, RTCA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Parse the raw RTCA data file
//  * 2. [Input & Preparation] Read and format phenotype metadata
//  * 3. [Core Analysis] Assign metadata to the RTCA object
//  * 4. [Visualization & Output] Plot individual well curves
//  * 5. [Core Analysis] Add experimental actions to the timeline
//  * 6. [Visualization & Output] Generate a plate-wide visualization

nextflow.enable.dsl = 2

process BIOC_RTCA_RTCA_IMPORT_ANNOTATE_AND_VISUALIZE {
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
    
    # Load required libraries
    library(RTCA)
    library(Biobase)
    
    # 1. Parse the raw RTCA data file from the working directory
    ofile <- "testOutput.csv"
    x <- parseRTCA(ofile)
    
    # 2. Read and format phenotype metadata from the working directory
    pfile <- "testOutputPhenoData.csv"
    pData <- read.csv(pfile, sep="\t", row.names="Well")
    metaData <- data.frame(labelDescription=c(
                             "Rack number",
                             "siRNA catalogue number",
                             "siRNA gene symbol",
                             "siRNA EntrezGene ID",
                             "siRNA targeting accession"
                             ))
    phData <- new("AnnotatedDataFrame", data=pData, varMetadata=metaData)
    
    # 3. Assign metadata to the RTCA object
    phenoData(x) <- phData
    
    # 4. Plot individual well curves and save to PDF
    pdf("well_curves_plot.pdf", width=7, height=6)
    plot(x[,1:4], type="l", col="black", lty=1:4, xlab="time point", ylab="Cell Index")
    dev.off()
    
    # 5. Add experimental actions to the timeline
    x <- addAction(x, 22, "trasfection")
    x <- addAction(x, 30, "medium change")
    
    # Extract and save the timeline summary
    tl <- timeline(x)
    writeLines(capture.output(print(tl)), "timeline_summary.txt")
    
    # 6. Generate a plate-wide visualization and save to PDF
    pdf("plate_view_plot.pdf", width=10, height=8)
    plateView(x, col="orange")
    dev.off()
    
    # Save the final annotated RTCA object as an RDS file
    saveRDS(x, "annotated_rtca.rds")

    writeLines(c(
        '"BIOC_RTCA_RTCA_IMPORT_ANNOTATE_AND_VISUALIZE":',
        paste0('    RTCA: ', as.character(packageVersion('RTCA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rtca_import_annotate_and_visualize.csv versions.yml
    """
}

workflow BIOC_RTCA_RTCA_IMPORT_ANNOTATE_AND_VISUALIZE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ testOutput.csv, testOutputPhenoData.csv ] ]

    main:
    BIOC_RTCA_RTCA_IMPORT_ANNOTATE_AND_VISUALIZE(ch_input)

    emit:
    tables   = BIOC_RTCA_RTCA_IMPORT_ANNOTATE_AND_VISUALIZE.out.tables
    plots    = BIOC_RTCA_RTCA_IMPORT_ANNOTATE_AND_VISUALIZE.out.plots
    objects  = BIOC_RTCA_RTCA_IMPORT_ANNOTATE_AND_VISUALIZE.out.objects
    versions = BIOC_RTCA_RTCA_IMPORT_ANNOTATE_AND_VISUALIZE.out.versions
}
