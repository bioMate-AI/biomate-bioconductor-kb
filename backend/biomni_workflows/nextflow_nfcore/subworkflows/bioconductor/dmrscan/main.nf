#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DMRScan
// This package detects significant differentially methylated regions (for both qualitative and quantit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DMRScan/inst/doc/DMRScan_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("DMRScan")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DMRSCAN {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dmrscan"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dmrscan:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dmrscan:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dmrscan_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dmrscan_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dmrscan_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DMRScan)
    library(jsonlite)


    # --- Data [] ---
    # Key functions: phenotype
    library(DMRScan)
    data(DMRScan.methylationData) ## Load methylation data from chromosome 22, with 52018 CpGs measured
    data(DMRScan.phenotypes) ## Load phenotype (end-point for methylation data)

    # --- Obs [] ---
    # Key functions: function, summary, binomial, logit
    #observations <- apply(DMRScan.methylationData,1,function(x,y){
    #                        summary(glm(y ~ x, 
    #                        family = binomial(link = "logit")))$coefficients[2,3]}, 
    #                                            y = DMRScan.phenotypes)

    observations <- apply(DMRScan.methylationData,1,function(x,y){
                            summary(lm(x ~ y))$coefficients[2,3]}, 
                                               y = DMRScan.phenotypes)
    head(observations)

    # --- Pos [] ---
    # Key functions: unlist
    pos <- matrix(as.integer(unlist(strsplit(names(observations),split="chr|[.]"))), 
                                                    ncol = 3, byrow = TRUE)[,-1] 
    head(pos)

    # --- Cache = True [] ---
    # Key functions: distance
    ## Minimum number of CpGs in a tested cluster 
    min.cpg <- 3  

    ## Maxium distance (in base-pairs) within a cluster 
    ## before it is broken up into two seperate cluster
    max.gap <- 750

    # --- Reg [] ---
    # Key functions: makeCpGregions
    regions <- makeCpGregions(observations  = observations, chr = pos[,1], pos = pos[,2], 
                                                  maxGap = 750, minCpG = 3)

    # --- Thres [] ---
    # Key functions: estimateWindowThreshold, sampling, siegmund
    window.sizes <- 3:7 ## Number of CpGs in the sliding windows 
    ## (can be either a single number or a sequence)
    n.CpG        <- sum(sapply(regions, length)) ## Number of CpGs to be tested
    ## Estimate the window threshold, based on the number of CpGs and window sizes 
    ## using important sampling
    window.thresholds.importancSampling <- estimateWindowThreshold(nProbe = n.CpG, windowSize = window.sizes, 
                                                                        method = "sampling", mcmc = 10000)

    ## Estimating the window threshold using the closed form expression

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dmrscan_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dmrscan_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dmrscan_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DMRSCAN:", paste0("    dmrscan: ", packageVersion("DMRScan"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmrscan_results.csv
    touch ${prefix}_dmrscan_output.rds
    echo "BIOC_DMRSCAN:" > versions.yml
    echo "    dmrscan: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DMRSCAN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DMRSCAN(ch_input)

    emit:
    results  = BIOC_DMRSCAN.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DMRSCAN.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DMRSCAN.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DMRSCAN.out.versions  // channel: path(versions.yml)
}
