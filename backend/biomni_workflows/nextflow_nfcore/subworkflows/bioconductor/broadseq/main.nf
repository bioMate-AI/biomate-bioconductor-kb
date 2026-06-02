#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: broadSeq
// This package helps user to do easily RNA-seq data analysis with multiple methods (usually which need
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/broadSeq/inst/doc/broadSeq.R
// Upstream  : ggplot2, vsn
// Downstream: none
//
// Install: BiocManager::install("broadSeq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BROADSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-broadseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-broadseq:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-broadseq:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_broadseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_broadseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_broadseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(broadSeq)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, assays, ggdensity, geom_vline, scale_x_log10, rowSums, counts, count
    knitr::opts_chunk$set(
      collapse = TRUE,
      comment = "#>"
    )
    assays(se)[["counts"]][,5] %>% ggpubr::ggdensity(y = "count")+
        ggplot2::geom_vline(xintercept = 10)+ggplot2::scale_x_log10()

    keep <- (assays(se)[["counts"]] >= 3) %>% rowSums() >= 5 
    # smallest Group Size is 5
    table(keep)
    se <- broadSeq::normalizeEdgerCPM(se ,method = "none",cpm.log = TRUE )
    ## The normalized values are added with the assay name "logCPM"
    SummarizedExperiment::assayNames(se)

    # --- Warning=false [] ---
    # Key functions: normalizeEdgerCPM, assayNames, assays, counts, logCPM, transformDESeq2, vst, normTransform
    se <- broadSeq::normalizeEdgerCPM(se , method = "TMM", cpm.log = FALSE )
    ## The normalized values are added with the assay name "TMM"
    SummarizedExperiment::assayNames(se)

    ## -----------------------------------------------------------------------------
    assays(se)[["counts"]][1:5,1:5]
    assays(se)[["TMM"]][1:5,1:5]
    assays(se)[["logCPM"]][1:5,1:5]
    se <- broadSeq::transformDESeq2(se,method = "vst"  )

    ## -----------------------------------------------------------------------------
    se <- broadSeq::transformDESeq2(se, method = "normTransform"  )
    #  se <- broadSeq::transformDESeq2(se, method = "rlog")

    ## -----------------------------------------------------------------------------
    SummarizedExperiment::assayNames(se)

    # --- Warning=false [] ---
    # Key functions: sampleAssay_plot, rremove, ggarrange, counts, stage, x.text, vst, logCPM
    p <- broadSeq::sampleAssay_plot(se[, se$species=="Mouse" ], 
                               assayName = "counts", fill = "stage", 
                               yscale = "log2")+ rremove("x.text")

    p1 <- broadSeq::sampleAssay_plot(se[, se$species=="Mouse"], 
                               assayName = "vst", fill = "stage")+ rremove("x.text")

    p2 <- broadSeq::sampleAssay_plot(se[, se$species=="Mouse"], 
                               assayName = "TMM", fill = "stage", 
                               yscale = "log10")+ rremove("x.text")
    jco <- broadSeq::genes_plot(se[,se$species == "Mouse"], 
                         features = c("Shh"), facet.by = "symbol", assayName =  "logCPM",
                         x = "stage",  fill="stage", add="dotplot", xlab = "", 
                         title = "Journal of Clinical Oncology", palette = "jco") 

    npg <- broadSeq::genes_plot(se[,se$species == "Mouse"], 
                         features = c("Shh"), facet.by = "symbol",assayName =  "logCPM",
                         x = "stage", fill="stage", add="dotplot", xlab = "",
                         title = "Nature Publishing Group", palette = "npg") 


    # --- Warning=false [] ---
    # Key functions: readRDS, colData, extdata, rat_vole_mouseSE_salmon.rds, broadSeq, rowData
    se <- readRDS(system.file("extdata","rat_vole_mouseSE_salmon.rds", package = "broadSeq"))

    # To reduce the run time, subset of the data used here
    se <- se[,colData(se)$species == "Mouse"]
    head(rownames(se))
    head(rowData(se))
    head(colData(se))
    table(colData(se)$stage)

    # --- Warning=false [] ---
    # Key functions: use_NOIseq, stage, genes_plot, filter, rotate_x_text, ggscatter, scale_x_log10, scale_y_log10
    result_Noiseq <- 
        use_NOIseq(se = se, 
               colData_id = "stage", control = "Bud", treatment = "Cap",
               rank = TRUE, 
               r = 10) # r is an argument of NOISeq::noiseqbio

    head(result_Noiseq)
    pg <- broadSeq::genes_plot(se, x = "stage", assayName =  "counts",  
               features = result_Noiseq %>% dplyr::filter(rank <5) %>% rownames(),
               fill="stage", facet.by = "symbol",
               palette="jco", add = "dotplot")+rotate_x_text()

    pg_sc <- ggscatter(result_Noiseq, x="Bud_mean", y="Cap_mean",color = "prob")+ 
        scale_x_log10()+scale_y_log10()

    pg+pg_sc
    # limma 
    ?use_limma_trend(se, colData_id, control, treatment, rank = FALSE, ...)
    ?use_limma_voom(se, colData_id, control, treatment, rank = FALSE, ...)


    # --- Warning=false [] ---
    # Key functions: use_multDE, stage, select, ends_with, dist, hclust, rank
    # First define a named list of functions
    funs <- list(limma_trend = use_limma_trend, limma_voom = use_limma_voom,
                 edgeR_exact = use_edgeR_exact, edgeR_glm = use_edgeR_GLM,
                 deseq2 = use_deseq2, 
                 DELocal = use_DELocal, noiseq = use_NOIseq, 
                 EBSeq = use_EBSeq) 



    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_broadseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_broadseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_broadseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BROADSEQ:", paste0("    broadseq: ", packageVersion("broadSeq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_broadseq_results.csv
    touch ${prefix}_broadseq_output.rds
    echo "BIOC_BROADSEQ:" > versions.yml
    echo "    broadseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BROADSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BROADSEQ(ch_input)

    emit:
    results  = BIOC_BROADSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BROADSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BROADSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BROADSEQ.out.versions  // channel: path(versions.yml)
}
