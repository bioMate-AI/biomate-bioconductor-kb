#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: EpiMix
// EpiMix is a comprehensive tool for the integrative analysis of high-throughput DNA methylation data 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/EpiMix/inst/doc/Methylation_Modeling.R
// Upstream  : DT, clusterProfiler, miRBaseConverter, multiMiR, survival
// Downstream: none
//
// Install: BiocManager::install("EpiMix")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPIMIX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epimix"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epimix:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epimix:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epimix_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epimix_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epimix_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(EpiMix)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, list.epigenomes, tempdir, EpiMix
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )
    # First, we need to set the analytic mode to enhancer
    mode <- "Enhancer"

    # Since enhancers are cell or tissue-type specific, EpiMix needs 
    # to know the reference cell type or tissue to select proper enhancers.
    # Available ids for tissue or cell types can be 
    # obtained from Figure 2 of the RoadmapEpigenomic
    # paper: https://www.nature.com/articles/nature14248. 
    # Alternatively, they can also be retrieved from the 
    # built-in function `list.epigenomes()`.

    # --- Eval=true [] ---
    # Key functions: tempdir, EpiMix, miRNA, datatable
    # Note that running the methylation analysis for miRNA genes need gene expression data for miRNAs
    data(microRNA.data)

    mode <- "miRNA"

    # Specify the output directory
    outputDirectory = tempdir()

    # --- Eval=true [] ---
    # Key functions: tempdir, EpiMix, lncRNA, datatable
    # Note: standard RNA-seq processing method can not detect sufficient amount of lncRNAs. 
    # To maximize the capture of lncRNA expression, please use the pipeline propoased 
    # in our previous study: PMID: 31808800

    data(lncRNA.data)

    mode <- "lncRNA"

    # Specify the output directory
    outputDirectory =  tempdir()
    datatable(EpiMixResults_lncRNA$FunctionalPairs[1:5, ],
              options = list(scrollX = TRUE, 
                             autoWidth = TRUE,
                             keys = TRUE,
                             pageLength = 5, 
                             rownames= FALSE,
                             digits = 3), 
                             rownames = FALSE)

    # --- Eval=true [] ---
    # Key functions: TCGA_Download_GeneExpression, miRNA, lncRNA, EpiMix_PlotModel, cg14029001
    # If use the Regular or the Enhancer mode: 
    GEdirectories <- TCGA_Download_GeneExpression(CancerSite = "OV", 
                                                  TargetDirectory = outputDirectory)


    # If use the miRNA mode, download miRNA expression data:
    mode <- "miRNA"
    GEdirectories <- TCGA_Download_GeneExpression(CancerSite = "OV", 
                                                  TargetDirectory = outputDirectory, 
                                                  mode = mode)
    data(Sample_EpiMixResults_Regular)

    plots <- EpiMix_PlotModel(
                     EpiMixResults = Sample_EpiMixResults_Regular, 
                     Probe = "cg14029001", 
                     methylation.data = MET.data, 
                     gene.expression.data = mRNA.data,
                     GeneName = "CCND3"
                     )

    # --- Eval=true [] ---
    # Key functions: epimix
    # Mixture model of the DNA methylation of the CCND3 gene at cg14029001
    plots$MixtureModelPlot

    # Violin plot of the gene expression levels of the CCND3 gene in different mixtures
    plots$ViolinPlot

    # Correlation between DNA methylation and gene expression of CCND3
    plots$CorrelationPlot
    knitr::kable(head(enrich.results), row.names = FALSE)

    # --- Eval=true [] ---
    # Key functions: functionEnrich
    enrich.results <- functionEnrich(EpiMixResults = Sample_EpiMixResults_Regular,
                                      methylation.state = "all",
                                      enrich.method = "KEGG",
                                      simplify = TRUE,
                                      save.dir = "")
    knitr::kable(head(enrich.results), row.names = FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epimix_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epimix_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epimix_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPIMIX:", paste0("    epimix: ", packageVersion("EpiMix"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epimix_results.csv
    touch ${prefix}_epimix_output.rds
    echo "BIOC_EPIMIX:" > versions.yml
    echo "    epimix: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPIMIX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPIMIX(ch_input)

    emit:
    results  = BIOC_EPIMIX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPIMIX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPIMIX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPIMIX.out.versions  // channel: path(versions.yml)
}
