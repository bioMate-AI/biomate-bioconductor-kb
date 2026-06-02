#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MCbiclust
// Custom made algorithm and associated methods for finding, visualising and analysing biclusters in la
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MCbiclust/inst/doc/MCbiclust_vignette.R
// Upstream  : GSVA, MASS, devtools, dplyr, gProfileR
// Downstream: none
//
// Install: BiocManager::install("MCbiclust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MCBICLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mcbiclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mcbiclust:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mcbiclust:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mcbiclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mcbiclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mcbiclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MCbiclust)
    library(CVEval)
    library(ForkClassifier)
    library(GOEnrichmentAnalysis)
    library(MultiSampleSortPrep)
    library(PC1Align)
    library(PC1VecFun)
    library(PointScoreCalc)
    library(SilhouetteClustGroups)
    library(ThresholdBic)
    library(jsonlite)

    # --- Cross-Validation and Gene Selection [] ---
    # Key functions: CVEval
    CCLE.cor.vec <- CVEval(
        gem.part = CCLE.mito,
        gem.all = CCLE_small,
        seed = CCLE.seed,
        splits = 10
    )
    top200 <- row.names(CCLE_small)[
        order(CCLE.cor.vec, decreasing = TRUE)[seq(200)]
    ]


    # --- Bicluster Extraction and Alignment [] ---
    # Key functions: PC1VecFun, ThresholdBic, PC1Align
    top.mat <- CCLE.mito[as.numeric(CCLE.hicor.genes), ]
    pc1.vec <- PC1VecFun(
        top.gem = top.mat,
        seed.sort = CCLE.samp.sort,
        n = 10
    )
    CCLE.bic <- ThresholdBic(
        cor.vec = CCLE.cor.vec,
        sort.order = CCLE.samp.sort,
        pc1 = pc1.vec,
        samp.sig = 0.05
    )
    pc1.aligned <- PC1Align(
        gem = CCLE_small,
        pc1 = pc1.vec,
        sort.order = CCLE.samp.sort,
        cor.vec = CCLE.cor.vec,
        bic = CCLE.bic
    )


    # --- Sample Classification [] ---
    # Key functions: ForkClassifier
    fork.status <- ForkClassifier(
        pc1.aligned,
        samp.num = length(CCLE.bic[[2]])
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mcbiclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mcbiclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mcbiclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MCBICLUST:", paste0("    mcbiclust: ", packageVersion("MCbiclust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mcbiclust_results.csv
    touch ${prefix}_mcbiclust_output.rds
    echo "BIOC_MCBICLUST:" > versions.yml
    echo "    mcbiclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MCBICLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MCBICLUST(ch_input)

    emit:
    results  = BIOC_MCBICLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MCBICLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MCBICLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MCBICLUST.out.versions  // channel: path(versions.yml)
}
