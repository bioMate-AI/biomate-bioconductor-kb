#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylKit
// methylKit is an R package for DNA methylation analysis and annotation from high-throughput bisulfite
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylKit/inst/doc/methylKit.R
// Upstream  : genomation
// Downstream: none
//
// Install: BiocManager::install("methylKit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLKIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylkit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylkit:1.32.1--r44_0' :
        'quay.io/biocontainers/bioconductor-methylkit:1.32.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylkit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylkit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylkit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(methylKit)
    library(PCASamples)
    library(jsonlite)

    # --- Quality Control and Filtering [] ---
    # Key functions: getMethylationStats, getCoverageStats, filterByCoverage
    getMethylationStats(myobj[[1]], plot = FALSE, both.strands = FALSE)
    getCoverageStats(myobj[[1]], plot = FALSE, both.strands = FALSE)
    filtered_myobj <- filterByCoverage(
        myobj,
        lo.count = 10,
        lo.perc = NULL,
        hi.count = NULL,
        hi.perc = 99.9
    )


    # --- Sample Merging and Clustering [] ---
    # Key functions: unite, getCorrelation, clusterSamples, PCASamples
    meth <- unite(filtered_myobj, destrand = FALSE)
    getCorrelation(meth, plot = FALSE)
    hc <- clusterSamples(
        meth,
        dist = "correlation",
        method = "ward",
        plot = FALSE
    )
    PCASamples(meth, screeplot = FALSE)


    # --- Batch Effect Correction [] ---
    # Key functions: assocComp, removeComp, percMethylation, reconstruct
    sample_annotation <- data.frame(
        batch_id = c("a", "a", "b", "b"),
        age = c(19, 34, 23, 40)
    )
    as_comp <- assocComp(mBase = meth, sample_annotation)
    new_obj <- removeComp(meth, comp = 1)
    mat <- percMethylation(new_obj)
    mat[mat == 100] <- 80
    corrected_obj <- reconstruct(mat, new_obj)


    # --- Differential Methylation Analysis [] ---
    # Key functions: calculateDiffMeth, getMethylDiff, diffMethPerChr
    my_diff <- calculateDiffMeth(corrected_obj)
    my_diff_hyper <- getMethylDiff(
        my_diff,
        difference = 25,
        qvalue = 0.01,
        type = "hyper"
    )
    my_diff_hypo <- getMethylDiff(
        my_diff,
        difference = 25,
        qvalue = 0.01,
        type = "hypo"
    )
    diff_chr <- diffMethPerChr(
        my_diff,
        plot = FALSE,
        qvalue.cutoff = 0.01,
        meth.cutoff = 25
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylkit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylkit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylkit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLKIT:", paste0("    methylkit: ", packageVersion("methylKit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylkit_results.csv
    touch ${prefix}_methylkit_output.rds
    echo "BIOC_METHYLKIT:" > versions.yml
    echo "    methylkit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLKIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLKIT(ch_input)

    emit:
    results  = BIOC_METHYLKIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLKIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLKIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLKIT.out.versions  // channel: path(versions.yml)
}
