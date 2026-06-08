#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Heatplus — legacy_heatmap
// Generate heatmaps using the older legacy functions heatmap_2 and heatmap_plus.
// Input: exprs_matrix.csv, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-heatplus:3.18.0--r45hdfd78af_0
// Requires: Heatplus
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Generate basic legacy heatmap using heatmap_2. 2. Generate annotated legacy heatmap using heatmap_plus

nextflow.enable.dsl = 2

process BIOC_HEATPLUS_LEGACY_HEATMAP {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
    # Load required library
    library(Heatplus)
    
    # Read user input files from the working directory
    # exprs_matrix.csv: numeric matrix of features (rows) by samples (columns)
    mm <- as.matrix(read.csv("exprs_matrix.csv", row.names = 1, check.names = FALSE))
    
    # sample_metadata.csv: data frame of sample annotations (rows = samples, columns = annotations)
    addvar <- read.csv("sample_metadata.csv", row.names = 1, check.names = FALSE)
    
    # Stage 1: Generate basic legacy heatmap using heatmap_2
    pdf("heatmap_2_basic.pdf")
    heatmap_2(mm)
    dev.off()
    
    pdf("heatmap_2_custom.pdf")
    heatmap_2(mm, do.dendro=c(FALSE, TRUE), legend=1, legfrac=12)
    dev.off()
    
    # Stage 2: Generate annotated legacy heatmap using heatmap_plus
    pdf("heatmap_plus_basic.pdf")
    heatmap_plus(mm)
    dev.off()
    
    pdf("heatmap_plus_annotated.pdf")
    heatmap_plus(mm, addvar=addvar, cov=ncol(addvar))
    dev.off()
    
    pdf("heatmap_plus_custom.pdf")
    heatmap_plus(mm, addvar=addvar, cov=ncol(addvar), h=20, col=RGBColVec(64))
    dev.off()

    writeLines(c(
        '"BIOC_HEATPLUS_LEGACY_HEATMAP":',
        paste0('    Heatplus: ', as.character(packageVersion('Heatplus')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_legacy_heatmap.csv versions.yml
    """
}

workflow BIOC_HEATPLUS_LEGACY_HEATMAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs_matrix.csv, sample_metadata.csv ] ]

    main:
    BIOC_HEATPLUS_LEGACY_HEATMAP(ch_input)

    emit:
    tables   = BIOC_HEATPLUS_LEGACY_HEATMAP.out.tables
    plots    = BIOC_HEATPLUS_LEGACY_HEATMAP.out.plots
    objects  = BIOC_HEATPLUS_LEGACY_HEATMAP.out.objects
    versions = BIOC_HEATPLUS_LEGACY_HEATMAP.out.versions
}
