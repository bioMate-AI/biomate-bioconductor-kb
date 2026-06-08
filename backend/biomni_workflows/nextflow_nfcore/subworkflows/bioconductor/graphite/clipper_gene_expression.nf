#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: graphite — clipper_gene_expression
// Identify significant pathways and find the most relevant altered gene signal paths using clipper.
// Input: ALL.rds
// Container: quay.io/biocontainers/bioconductor-graphite:1.56.0--r45hdfd78af_0
// Requires: Biobase, a4Preproc, clipper, graphite
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define sample classes (1 and 2) based on phenotype
//  * 2. [Core Analysis] Extract expression matrix and format rownames with the "ENTREZID:" prefix
//  * 3. [Input & Preparation] Load KEGG pathways and select target pathways
//  * 4. [Core Analysis] Run clipper analysis using runClipper

nextflow.enable.dsl = 2

process BIOC_GRAPHITE_CLIPPER_GENE_EXPRESSION {
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
    
    # Load required libraries
    library(Biobase)
    library(graphite)
    library(clipper)
    library(a4Preproc)
    
    # 1. Read the user input file
    ALL <- readRDS("ALL.rds")
    
    # 2. Define sample classes (1 and 2) based on phenotype
    pheno <- as(phenoData(ALL), "data.frame")
    samples <- unlist(lapply(c("NEG", "BCR/ABL"), function(t) {
      which(grepl("^B\\\\d*", pheno\$BT) & (pheno\$mol.biol == t))[1:10]
    }))
    classes <- c(rep(1,10), rep(2,10))
    
    # 3. Extract expression matrix and format rownames with the "ENTREZID:" prefix
    expr <- exprs(ALL)[,samples]
    rownames(expr) <- paste("ENTREZID",
                            featureData(addGeneInfo(ALL))\$ENTREZID,
                            sep = ":")
    
    # 4. Load KEGG pathways and select target pathways
    k <- as.list(pathways("hsapiens", "kegg"))
    selection <- c("Bladder cancer", "Hippo signaling pathway - multiple species")
    selected <- k[selection]
    names(selected) <- c("Bladder cancer", "Hippo signaling")
    
    # 5. Run clipper analysis using runClipper
    clipped <- runClipper(selected, expr, classes, "mean", pathThr = 0.1)
    
    # 6. Write named output files
    saveRDS(clipped, "clipper_results.rds")
    
    # Format and save the results table
    if (!is.null(clipped\$results)) {
      resClip <- do.call(rbind, clipped\$results)
      write.csv(resClip, "clipper_results.csv", row.names = TRUE)
    }

    writeLines(c(
        '"BIOC_GRAPHITE_CLIPPER_GENE_EXPRESSION":',
        paste0('    graphite: ', as.character(packageVersion('graphite')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clipper_gene_expression.csv versions.yml
    """
}

workflow BIOC_GRAPHITE_CLIPPER_GENE_EXPRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ALL.rds ] ]

    main:
    BIOC_GRAPHITE_CLIPPER_GENE_EXPRESSION(ch_input)

    emit:
    tables   = BIOC_GRAPHITE_CLIPPER_GENE_EXPRESSION.out.tables
    plots    = BIOC_GRAPHITE_CLIPPER_GENE_EXPRESSION.out.plots
    objects  = BIOC_GRAPHITE_CLIPPER_GENE_EXPRESSION.out.objects
    versions = BIOC_GRAPHITE_CLIPPER_GENE_EXPRESSION.out.versions
}
