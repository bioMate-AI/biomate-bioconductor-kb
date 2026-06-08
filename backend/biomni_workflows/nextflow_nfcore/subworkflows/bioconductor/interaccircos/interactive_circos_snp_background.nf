#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: interacCircos — interactive_circos_snp_background
// Create an interactive Circos plot displaying SNP data points overlaid on a background track.
// Input: snp_data.csv
// Container: quay.io/biocontainers/bioconductor-interaccircos:1.20.0--r45hdfd78af_0
// Requires: htmlwidgets, interacCircos
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the interacCircos library
//  * 2. [Input & Preparation] Load the SNP data
//  * 3. [Core Analysis] Combine the SNP track and background track using the plus operator
//  * 4. [Visualization & Output] Generate the interactive Circos plot using Circos

nextflow.enable.dsl = 2

process BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_SNP_BACKGROUND {
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
    
    # 1. Load the interacCircos library
    library(interacCircos)
    
    # 2. Load the SNP data
    # Read the user-provided snp_data.csv file.
    # We assign it to the variable name 'snpExample' to match the documented code's argument 'data = snpExample' exactly.
    snpExample <- read.csv("snp_data.csv", stringsAsFactors = FALSE)
    
    # 3. Combine the SNP track and background track using the plus operator
    # 4. Generate the interactive Circos plot using Circos
    circos_plot <- Circos(moduleList=CircosSnp('SNP01', minRadius =150, 
          maxRadius = 190, data = snpExample, SNPFillColor= "#9ACD32", 
          circleSize= 2, SNPAxisColor= "#B8B8B8", SNPAxisWidth= 0.5, 
          animationDisplay=TRUE, animationTime= 2000, animationDelay= 0, 
          animationType= "linear") + 
          CircosBackground('BG01', minRadius = 145, maxRadius = 200),
          width = 700, height = 550)
    
    # 5. Write named output files for the meaningful results
    # Save the Circos htmlwidget object as an RDS file
    saveRDS(circos_plot, "circos_plot.rds")
    
    # Save the interactive plot as an HTML file using htmlwidgets
    tryCatch({
      if (requireNamespace("htmlwidgets", quietly = TRUE)) {
        htmlwidgets::saveWidget(circos_plot, "circos_plot.html", selfcontained = TRUE)
      }
    }, error = function(e) {
      warning("Could not save HTML widget: ", e\$message)
    })

    writeLines(c(
        '"BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_SNP_BACKGROUND":',
        paste0('    interacCircos: ', as.character(packageVersion('interacCircos')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_interactive_circos_snp_background.csv versions.yml
    """
}

workflow BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_SNP_BACKGROUND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ snp_data.csv ] ]

    main:
    BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_SNP_BACKGROUND(ch_input)

    emit:
    tables   = BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_SNP_BACKGROUND.out.tables
    plots    = BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_SNP_BACKGROUND.out.plots
    objects  = BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_SNP_BACKGROUND.out.objects
    versions = BIOC_INTERACCIRCOS_INTERACTIVE_CIRCOS_SNP_BACKGROUND.out.versions
}
