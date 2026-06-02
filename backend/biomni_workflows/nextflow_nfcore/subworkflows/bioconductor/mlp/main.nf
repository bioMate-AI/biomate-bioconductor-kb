#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MLP
// Pathway analysis based on p-values associated to genes from a genes expression analysis of interest.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MLP/inst/doc/UsingMLP.R
// Upstream  : AnnotationDbi, limma
// Downstream: none
//
// Install: BiocManager::install("MLP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MLP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mlp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mlp:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mlp:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mlp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mlp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mlp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MLP)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: annotation
    pathExampleData <- system.file("exampleFiles", "expressionSetGcrma.rda", package = "MLP")
      load(pathExampleData)
      annotation(expressionSetGcrma) <- "mouse4302"
    # --- Preparepvalues [] ---
    # Key functions: factor, pData, lmFit, exprs, eBayes
    ### calculation of the statistics values via limma
      group <- as.numeric(factor(pData(expressionSetGcrma)$subGroup1, levels = c("WT", "KO")))-1
      design <- model.matrix(~group)
      fit <- lmFit(exprs(expressionSetGcrma), design)
      fit2 <- eBayes(fit)
    # --- Creategenesets [] ---
    # Key functions: getGeneSets
    geneSet <- getGeneSets(species = "Mouse",
    		geneSetSource = "GOCC",
    		entrezIdentifiers = names(pvalues)
    )
    tail(geneSet, 3)
    # --- Showattributes [] ---
    # Key functions: attributes
    str(attributes(geneSet))
    # --- Runmlp [] ---
    # Key functions: MLP
    set.seed(111)
    mlpOut <- MLP(
    		geneSet = geneSet,
    		geneStatistic = pvalues,
    		minGenes = 5,
    # --- Showattributes [] ---
    # Key functions: attributes
    str(attributes(mlpOut))
    # --- Quantilecurves [] ---
    # Key functions: off
    pdf("mlpQuantileCurves.pdf", width = 10, height = 10)
      plot(mlpOut, type = "quantileCurves")
      tmp <- dev.off()
    # --- Barplot [] ---
    # Key functions: off
    pdf("mlpBarplot.pdf", width = 10, height = 10)
      op <- par(mar = c(30, 10, 6, 2))
      plot(mlpOut, type = "barplot", ylab = "-log10(gene set p-value)")
      par(op)
      tmp <- dev.off()
    # --- Gograph [] ---
    # Key functions: off
    pdf("mlpGOgraph.pdf", width = 8, height = 6)
      op <- par(mar = c(0, 0, 0, 0))
      plot(mlpOut, type = "GOgraph", nRow = 10, nCutDescPath = 15)
      par(op)
      tmp <- dev.off()
    # --- Genesignificance [] ---
    # Key functions: plotGeneSetSignificance, annotation, off
    geneSetID <- rownames(mlpOut)[1]
    pdf("geneSignificance.pdf", width = 10, height = 10)
    op <- par(mar = c(25, 10, 6, 2))
    plotGeneSetSignificance(
    		geneSet = geneSet,

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mlp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mlp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mlp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MLP:", paste0("    mlp: ", packageVersion("MLP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mlp_results.csv
    touch ${prefix}_mlp_output.rds
    echo "BIOC_MLP:" > versions.yml
    echo "    mlp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MLP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MLP(ch_input)

    emit:
    results  = BIOC_MLP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MLP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MLP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MLP.out.versions  // channel: path(versions.yml)
}
