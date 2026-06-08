#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PanomiR — custom_pathway_table_generation
// Create a customized pathway-gene association table from external sources or GMT files to replace the default background pathway table.
// Input: pathways.gmt
// Container: quay.io/biocontainers/bioconductor-panomir:1.14.0--r45hdfd78af_0
// Requires: GSEABase, PanomiR
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import the GMT file as a GeneSetCollection using getGmt
//  * 2. [Core Analysis] Convert the GeneSetCollection into a pathway-gene association table using tableFromGSC

nextflow.enable.dsl = 2

process BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_GENERATION {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # Load required libraries
    library(PanomiR)
    library(GSEABase)
    
    # Define input file
    gmt_file <- "pathways.gmt"
    
    # Check if input file exists
    if (!file.exists(gmt_file)) {
      stop(paste("Required input file missing:", gmt_file))
    }
    
    # 1. Import the GMT file as a GeneSetCollection using getGmt
    yourGeneSetCollection <- getGmt(gmt_file)
    
    # 2. Convert the GeneSetCollection into a pathway-gene association table using tableFromGSC
    newPathGeneTable <- tableFromGSC(yourGeneSetCollection)
    
    # Write the output to a CSV file
    write.csv(newPathGeneTable, "custom_pathway_gene_table.csv", row.names = FALSE)
    
    message("Workflow completed successfully. Output saved to 'custom_pathway_gene_table.csv'.")

    writeLines(c(
        '"BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_GENERATION":',
        paste0('    PanomiR: ', as.character(packageVersion('PanomiR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_pathway_table_generation.csv versions.yml
    """
}

workflow BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pathways.gmt ] ]

    main:
    BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_GENERATION(ch_input)

    emit:
    tables   = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_GENERATION.out.tables
    plots    = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_GENERATION.out.plots
    objects  = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_GENERATION.out.objects
    versions = BIOC_PANOMIR_CUSTOM_PATHWAY_TABLE_GENERATION.out.versions
}
