#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneBreak — dataframe_input_pipeline
// Detect and analyze recurrent gene breakpoints starting from custom copy number data stored in standard R data.frames.
// Input: segmented.txt, called.txt, ens.gene.ann.hg18
// Container: quay.io/biocontainers/bioconductor-genebreak:1.40.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CGHcall, GeneBreak
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load segmented and called data.frames and extract breakpoints using getBreakpoints()
//  * 2. [Core Analysis] Filter out non-CNA-associated breakpoints using bpFilter()
//  * 3. [Core Analysis] Map genomic features to genes using addGeneAnnotation()
//  * 4. [Core Analysis] Identify gene-associated breakpoints using bpGenes()
//  * 5. [Core Analysis] Calculate cohort-based statistics at the gene level using bpStats() with the Gilbert method
//  * 6. [Core Analysis] Calculate cohort-based statistics at the feature level using bpStats() with the BH method
//  * 7. [Visualization & Output] Plot breakpoint frequencies across the chromosome using bpPlot()

nextflow.enable.dsl = 2

process BIOC_GENEBREAK_DATAFRAME_INPUT_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("GeneBreak", "CGHcall")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library(GeneBreak)
    library(CGHcall)
    
    # 1. Load segmented and called data.frames from the working directory
    segmented <- read.delim("segmented.txt", header = TRUE, sep = "\t", check.names = FALSE)
    called <- read.delim("called.txt", header = TRUE, sep = "\t", check.names = FALSE)
    
    # Extract breakpoints using getBreakpoints()
    breakpoints <- getBreakpoints( data = segmented, data2 = called )
    
    # 2. Filter out non-CNA-associated breakpoints using bpFilter()
    breakpointsFiltered <- bpFilter( breakpoints, filter = "CNA-ass" )
    
    # 3. Map genomic features to genes using addGeneAnnotation()
    # Read the gene annotation file from the working directory
    ens.gene.ann.hg18 <- read.delim("ens.gene.ann.hg18", header = TRUE, sep = "\t", check.names = FALSE)
    
    breakpointsAnnotated <- addGeneAnnotation( breakpointsFiltered, ens.gene.ann.hg18 )
    
    # 4. Identify gene-associated breakpoints using bpGenes()
    breakpointGenes <- bpGenes( breakpointsAnnotated )
    
    # 5. Calculate cohort-based statistics at the gene level using bpStats() with the Gilbert method
    breakpointStatistics <- bpStats( breakpointGenes, level = "gene", method = "Gilbert" )
    
    # 6. Calculate cohort-based statistics at the feature level using bpStats() with the BH method
    breakpointStatistics <- bpStats( breakpointStatistics, level = "feature", method = "BH" )
    
    # 7. Plot breakpoint frequencies across the chromosome using bpPlot() and save to PDF
    pdf("breakpoint_plot.pdf", width = 10, height = 7)
    bpPlot( breakpointStatistics, fdr.threshold = 0.1 )
    dev.off()
    
    # Write meaningful results to output files
    # Save the final breakpoint statistics object
    saveRDS(breakpointStatistics, file = "breakpoint_statistics.rds")
    
    # Save recurrently affected genes
    recurrent_genes_df <- recurrentGenes( breakpointStatistics )
    write.csv(recurrent_genes_df, file = "recurrent_genes.csv", row.names = FALSE)
    
    # Save feature-level breakpoint information
    feature_info_df <- featureInfo( breakpointStatistics )
    write.csv(feature_info_df, file = "feature_info.csv", row.names = TRUE)
    
    # Save gene-level breakpoint information
    gene_info_df <- geneInfo( breakpointGenes )
    write.csv(gene_info_df, file = "gene_info.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_GENEBREAK_DATAFRAME_INPUT_PIPELINE":',
        paste0('    GeneBreak: ', as.character(packageVersion('GeneBreak')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dataframe_input_pipeline.csv versions.yml
    """
}

workflow BIOC_GENEBREAK_DATAFRAME_INPUT_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ segmented.txt, called.txt, ens.gene.ann.hg18 ] ]

    main:
    BIOC_GENEBREAK_DATAFRAME_INPUT_PIPELINE(ch_input)

    emit:
    tables   = BIOC_GENEBREAK_DATAFRAME_INPUT_PIPELINE.out.tables
    plots    = BIOC_GENEBREAK_DATAFRAME_INPUT_PIPELINE.out.plots
    objects  = BIOC_GENEBREAK_DATAFRAME_INPUT_PIPELINE.out.objects
    versions = BIOC_GENEBREAK_DATAFRAME_INPUT_PIPELINE.out.versions
}
