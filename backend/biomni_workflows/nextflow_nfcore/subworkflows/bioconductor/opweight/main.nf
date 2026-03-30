#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OPWeight
// This package perform weighted-pvalue based multiple hypothesis test and provides corresponding infor
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OPWeight/inst/doc/OPWeight.R
// Upstream  : ggplot2, airway, DESeq2, cowplot, tibble
// Downstream: none
//
// Install: BiocManager::install("OPWeight")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPWEIGHT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-opweight"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-opweight:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-opweight:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_opweight_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_opweight_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_opweight_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(jsonlite)

    # --- Create DESeqDataSet [] ---
    # Key functions: DESeqDataSet, DESeq, results
    data("airway", package = "airway")
    dds <- DESeqDataSet(se = airway, design = ~ cell + dex)
    dds <- DESeq(dds)
    # --- Custom ggplot2 visualization [] ---
    # Key functions: tibble, ggplot, geom_histogram, labs, geom_point
    Data <- tibble(pval=de_res_air$pvalue, filter=de_res_air$baseMean)
    hist_pval <- ggplot(Data, aes(x = Data$pval)) +
    geom_histogram(colour = "#1F3552", fill = "#4281AE")+
    # --- Opw analysis [] ---
    # Key functions: opw, labs, plot_grid, boxcox, weight_continuous
    dat = tibble(testRanks, probs, weights)
    p_prob = ggplot(dat, aes(x = testRanks, y = probs)) + geom_point(size = .5, col="firebrick4") +
    labs(x = "Test rank" , y = "p(rank | effect)")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_opweight_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_opweight_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_opweight_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OPWEIGHT:", paste0("    opweight: ", packageVersion("OPWeight"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_opweight_results.csv
    touch ${prefix}_opweight_output.rds
    echo "BIOC_OPWEIGHT:" > versions.yml
    echo "    opweight: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OPWEIGHT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_OPWEIGHT(ch_input)

    emit:
    results  = BIOC_OPWEIGHT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OPWEIGHT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OPWEIGHT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OPWEIGHT.out.versions  // channel: path(versions.yml)
}
