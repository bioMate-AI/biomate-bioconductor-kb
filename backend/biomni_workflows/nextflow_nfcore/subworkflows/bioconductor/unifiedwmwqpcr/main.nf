#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: unifiedWMWqPCR
// This packages implements the unified Wilcoxon-Mann-Whitney Test for qPCR data. This modified test al
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/unifiedWMWqPCR/inst/doc/unifiedWMWqPCR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("unifiedWMWqPCR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_UNIFIEDWMWQPCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-unifiedwmwqpcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-unifiedwmwqpcr:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-unifiedwmwqpcr:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_unifiedwmwqpcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_unifiedwmwqpcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_unifiedwmwqpcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(P)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library('unifiedWMWqPCR')
    data(NBmat)
    dim(NBmat)
    table(NBgroups)
    max(NBmat)
    # --- Uwmw [] ---
    # Key functions: uWMW
    uWMW.out <- uWMW(NBmat, groups = NBgroups)
    # --- Adjust [] ---
    # Key functions: adjust
    adj.pvalues <- p.adjust(uWMW.out@p.value, method = "BH")
    selection.id <- match(selection.miRNA, names(uWMW.out))
    adj.pvalues[selection.id]
    # --- Uwmw [] ---
    # Key functions: uWMW
    uWMW.out2 <- uWMW(NBmat, groups = NBgroups,
    housekeeping.names = housekeeping.miRNA)
    # --- Volcano [] ---
    # Key functions: volcanoplot
    volcanoplot(uWMW.out, add.ref = c("both"), ref.x = c(-log(2),log(2)),
    ref.y = -log10(0.001))
    # --- Forest [] ---
    # Key functions: expression, P, forestplot
    x.label <- expression("estimated "*P(Y[MNA] < Y[MNSC]))
    forestplot(uWMW.out, estimate = "p", order = selection.id, xlab = x.label)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_unifiedwmwqpcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_unifiedwmwqpcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_unifiedwmwqpcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_UNIFIEDWMWQPCR:", paste0("    unifiedwmwqpcr: ", packageVersion("unifiedWMWqPCR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_unifiedwmwqpcr_results.csv
    touch ${prefix}_unifiedwmwqpcr_output.rds
    echo "BIOC_UNIFIEDWMWQPCR:" > versions.yml
    echo "    unifiedwmwqpcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_UNIFIEDWMWQPCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_UNIFIEDWMWQPCR(ch_input)

    emit:
    results  = BIOC_UNIFIEDWMWQPCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_UNIFIEDWMWQPCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_UNIFIEDWMWQPCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_UNIFIEDWMWQPCR.out.versions  // channel: path(versions.yml)
}
