#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MIRit
// MIRit is an R package that provides several methods for investigating the relationships between miRN
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MIRit/inst/doc/MIRit.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("MIRit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIRIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mirit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mirit:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mirit:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_mirit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mirit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mirit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MIRit)
    library(jsonlite)


    # --- Example [] ---
    # Key functions: identical
    ## load count matrix for genes
    data(geneCounts, package = "MIRit")

    ## load count matrix for miRNAs
    data(mirnaCounts, package = "MIRit")
    ## print a table for gene expression matrix
    knitr::kable(geneCounts[seq(5), seq(5)], digits = 2, caption = "Gene expression matrix. An expression matrix containing normalized values, with row names according to hgnc.")
    ## print a table for miRNA expression matrix
    knitr::kable(mirnaCounts[seq(5), seq(5)], digits = 2, caption = "MiRNA expression matrix. An expression matrix containing normalized values, with row names according to miRBase.")
    ## print sample names in geneCounts
    colnames(geneCounts)

    ## print sample names in mirnaCounts
    colnames(mirnaCounts)

    ## check if samples in geneCounts are equal to those in mirnaCounts
    identical(colnames(geneCounts), colnames(mirnaCounts))

    # --- Metadata [] ---
    # Key functions: rep, Sample_, MirnaExperiment, plotDimensions, ggarrange, genes, disease, microRNA
    ## create a data.frame containing sample metadata
    meta <- data.frame(primary = colnames(mirnaCounts),
                       mirnaCol = colnames(mirnaCounts),
                       geneCol = colnames(geneCounts),
                       disease = c(rep("PTC", 8), rep("NTH", 8)),
                       patient = c(rep(paste("Sample_", seq(8), sep = ""), 2)))
    ## create the MirnaExperiment object
    experiment <- MirnaExperiment(mirnaExpr = mirnaCounts,
                                  geneExpr = geneCounts,
                                  samplesMetadata = meta,
                                  pairedSamples = TRUE)
    geneMDS <- plotDimensions(experiment,
                              assay = "genes",
                              condition = "disease",
                              title = "MDS plot for genes")

    mirnaMDS <- plotDimensions(experiment,
                               assay = "microRNA",
                               condition = "disease",
                               title = "MDS plot for miRNAs")

    # --- Diffexp [] ---
    # Key functions: performGeneDE, performMirnaDE, disease, geneDE, mirnaDE, plotVolcano, ggarrange, genes
    ## perform differential expression for genes
    experiment <- performGeneDE(experiment,
                                group = "disease",
                                contrast = "PTC-NTH",
                                design = model,
                                pCutoff = 0.01)

    ## perform differential expression for miRNAs
    # --- Species [] ---
    # Key functions: supportedOrganisms, enrichGenes, enrichmentResults
    ## list available species for Reactome database
    supportedOrganisms("Reactome")
    ## perform over-representation analysis with GO
    ora <- enrichGenes(experiment,
                       method = "ORA",
                       database = "GO",
                       organism = "Homo sapiens")
    ## set seed for reproducible results
    set.seed(1234)

    ## perform gene-set enrichment analysis with KEGG
    gse <- enrichGenes(experiment,
                       method = "GSEA",
                       database = "KEGG",
                       organism = "Homo sapiens")
    ## display the results of GSEA
    knitr::kable(enrichmentResults(gse), digits = 2, caption = "GSEA results. A table listing the affected KEGG pathways in thyroid cancer.")

    # --- Ora Dot [] ---
    # Key functions: enrichmentDotplot, gseaPlot, loadExamples, mirnaIntegration, correlation
    ## create a dot plot for ORA
    enrichmentDotplot(ora$downregulated, title = "Depleted functions")
    ## create a GSEA plot
    gseaPlot(gse, "Thyroid hormone synthesis", rankingMetric = TRUE)
    experiment <- loadExamples()
    ## perform a correlation analysis
    experiment <- mirnaIntegration(experiment, test = "correlation")

    # --- Correlation Results [] ---
    # Key functions: integration, plotCorrelation, ggarrange, disease, mirnaIntegration, association, none, fry
    ## extract correlation results
    integrationResults <- integration(experiment)

    ## take a look at correlation results
    head(integrationResults)
    ## plot the correlation between miR-146b-5p and DIO2
    cor1 <- plotCorrelation(experiment,
                            mirna = "hsa-miR-146b-5p",
                            gene = "DIO2",
                            condition = "disease")

    ## plot the correlation between miR-146b-3p and PAX8

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mirit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mirit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mirit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIRIT:", paste0("    mirit: ", packageVersion("MIRit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirit_results.csv
    touch ${prefix}_mirit_output.rds
    echo "BIOC_MIRIT:" > versions.yml
    echo "    mirit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIRIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_MIRIT(ch_input)

    emit:
    results  = BIOC_MIRIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIRIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIRIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIRIT.out.versions  // channel: path(versions.yml)
}
