#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CEMiTool — comprehensive_coexpression_analysis
// Run a complete co-expression module identification analysis including sample annotation, gene set enrichment, over-representation analysis, and interaction netw
// Input: expression_data.csv, sample_annotation.csv, pathways.gmt, interactions.tsv
// Container: quay.io/biocontainers/bioconductor-cemitool:1.34.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CEMiTool, ggplot2
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Load expression, sample annotation, GMT pathway, and interaction data. 2. Run the unified cemitool function with all inputs and pa

nextflow.enable.dsl = 2

process BIOC_CEMITOOL_COMPREHENSIVE_COEXPRESSION_ANALYSIS {
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
    library("CEMiTool")
    library(ggplot2)
    
    # Load expression data
    # Expects a CSV with gene symbols in the first column (row names) and samples in columns
    expr0 <- read.csv("expression_data.csv", row.names = 1, check.names = FALSE)
    
    # Load sample annotation data
    # Expects columns mapping sample names to classes/phenotypes
    sample_annot <- read.csv("sample_annotation.csv", check.names = FALSE)
    
    # Read GMT file for over-representation analysis (ORA)
    gmt_in <- read_gmt("pathways.gmt")
    
    # Read interactions file
    # Expects a tab-separated file with two columns for interacting gene pairs
    int_df <- read.delim("interactions.tsv", header = TRUE, sep = "\t", check.names = FALSE)
    
    # Run cemitool co-expression analysis pipeline
    cem <- cemitool(expr0, sample_annot, gmt_in, interactions=int_df,
                    filter=TRUE, plot=TRUE, verbose=TRUE)
    
    # Create report as HTML document
    generate_report(cem, directory="./Report")
    
    # Write analysis results into files
    write_files(cem, directory="./Tables")
    
    # Save all plots
    save_plots(cem, "all", directory="./Plots")
    
    # Save the CEMiTool object as an RDS file for downstream R analysis
    saveRDS(cem, file = "cemitool_results.rds")

    writeLines(c(
        '"BIOC_CEMITOOL_COMPREHENSIVE_COEXPRESSION_ANALYSIS":',
        paste0('    CEMiTool: ', as.character(packageVersion('CEMiTool')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_comprehensive_coexpression_analysis.csv versions.yml
    """
}

workflow BIOC_CEMITOOL_COMPREHENSIVE_COEXPRESSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ expression_data.csv, sample_annotation.csv, pathways.gmt, interactions.tsv ] ]

    main:
    BIOC_CEMITOOL_COMPREHENSIVE_COEXPRESSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_CEMITOOL_COMPREHENSIVE_COEXPRESSION_ANALYSIS.out.tables
    plots    = BIOC_CEMITOOL_COMPREHENSIVE_COEXPRESSION_ANALYSIS.out.plots
    objects  = BIOC_CEMITOOL_COMPREHENSIVE_COEXPRESSION_ANALYSIS.out.objects
    versions = BIOC_CEMITOOL_COMPREHENSIVE_COEXPRESSION_ANALYSIS.out.versions
}
