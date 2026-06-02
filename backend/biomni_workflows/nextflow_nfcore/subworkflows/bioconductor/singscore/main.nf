#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: singscore
// A simple single-sample gene signature scoring method that uses rank-based statistics to analyze the 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/singscore/inst/doc/singscore.R
// Upstream  : GSEABase
// Downstream: none
//
// Install: BiocManager::install("singscore")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SINGSCORE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-singscore"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-singscore:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-singscore:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_singscore_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_singscore_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_singscore_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(singscore)
    library(jsonlite)


    # --- Load Dataset [] ---
    # Key functions: geneIds, rankGenes, simpleScore, getStableGenes, genes, abline
    library(singscore)
    library(GSEABase)
    # The example expression dataset and gene signatures are included in the package
    # distribution, one can directly access them using the variable names

    # To see the description of 'tgfb_expr_10_se','tgfb_gs_up','tgfb_gs_dn', look at 
    # their help pages using:

    # ?tgfb_expr_10_se
    # ?tgfb_gs_up
    # The recommended method for dealing with ties in ranking is 'min', you can
    # change by specifying 'tiesMethod' parameter for rankGenes function.
    rankData <- rankGenes(tgfb_expr_10_se)

    # Given the ranked data and gene signature, simpleScore returns the scores and 
    # dispersions for each sample
    scoredf <- simpleScore(rankData, upSet = tgfb_gs_up, downSet = tgfb_gs_dn)
    scoredf

    # To view more details of the simpleScore, use ?simpleScore

    # --- Plotdt [] ---
    # Key functions: plotRankDensity, plotDispersion
    #  You can provide the upSet alone when working with unpaired gene-sets 
    # We plot the second sample in rankData, view it by 
    head(rankData[,2,drop = FALSE])

    plotRankDensity(rankData[,2,drop = FALSE], upSet = tgfb_gs_up, 
                    downSet = tgfb_gs_dn, isInteractive = FALSE)
    #  Get the annotations of samples by their sample names
    tgfbAnnot <- data.frame(SampleID = colnames(tgfb_expr_10_se),
                           Type = NA)
    tgfbAnnot$Type[grepl("Ctrl", tgfbAnnot$SampleID)] = "Control"
    tgfbAnnot$Type[grepl("TGFb", tgfbAnnot$SampleID)] = "TGFb"

    # Sample annotations
    tgfbAnnot$Type

    plotDispersion(scoredf,annot = tgfbAnnot$Type,isInteractive = FALSE)

    # --- Load Ccle [] ---
    # Key functions: plotScoreLandscape
    plotScoreLandscape(scoredf_ccle_epi, scoredf_ccle_mes, 
                       scorenames = c('ccle-EPI','ccle-MES'),hexMin = 10)
    tcgaLandscape <- plotScoreLandscape(scoredf_tcga_epi, scoredf_tcga_mes, 
                       scorenames = c('tcga_EPI','tcga_MES'), isInteractive = FALSE)

    tcgaLandscape

    # To get an interactive version of plot, set isInteractive = TRUE

    # --- Project Score [] ---
    # Key functions: projectScoreLandscape
    # Project on the above generated 'tcgaLandscape' plot
    projectScoreLandscape(plotObj = tcgaLandscape, scoredf_ccle_epi, 
                          scoredf_ccle_mes,
                          subSamples = rownames(scoredf_ccle_epi)[c(1,4,5)],
                          annot = rownames(scoredf_ccle_epi)[c(1,4,5)], 
                          sampleLabels = NULL,
                          isInteractive = FALSE)
    projectScoreLandscape(plotObj = tcgaLandscape, scoredf_ccle_epi, scoredf_ccle_mes,
                          subSamples = rownames(scoredf_ccle_epi)[c(1,4,5,8,9)],
                          sampleLabels = c('l1','l2','l3','l4','l5'),
                          annot = rownames(scoredf_ccle_epi)[c(1,4,5,8,9)], 
                          isInteractive = FALSE)

    # --- Pvalue [] ---
    # Key functions: bplapply, detectCores, generateNull, SnowParam, simpleScore, getPvals
    # tgfb_gs_up : up regulated gene set in the tgfb gene signature
    # tgfb_gs_dn : down regulated gene set in the tgfb gene signature

    # This permutation function uses BiocParallel::bplapply() parallel function, by 
    # supplying the first 5 columns of rankData, we generate Null distribution for 
    # the first 5 samples.

    # detect how many CPU cores are available for your machine
    # parallel::detectCores()

    pvals <- getPvals(permuteResult, scoredf, subSamples = 1:5)

    # getPval returns p-values for each individual sample.
    # show the p-values for first 5 samples
    pvals

    # --- Plot Null1 [] ---
    # Key functions: plotNull
    plotNull(permuteResult, scoredf, pvals, sampleNames = names(pvals)[1])
    # plot the null distributions for the first 2 samples and the p-values
    # We can see from the plot, the control samples are not significant and TGFb 
    # samples are very significant with very low p-values
    plotNull(permuteResult, scoredf, pvals, sampleNames = names(pvals)[1:2])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_singscore_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_singscore_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_singscore_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SINGSCORE:", paste0("    singscore: ", packageVersion("singscore"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_singscore_results.csv
    touch ${prefix}_singscore_output.rds
    echo "BIOC_SINGSCORE:" > versions.yml
    echo "    singscore: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SINGSCORE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SINGSCORE(ch_input)

    emit:
    results  = BIOC_SINGSCORE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SINGSCORE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SINGSCORE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SINGSCORE.out.versions  // channel: path(versions.yml)
}
