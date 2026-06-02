#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DiffBind
// Compute differentially bound sites from multiple ChIP-seq experiments using affinity (quantitative) 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DiffBind/inst/doc/DiffBind.R
// Upstream  : xtable
// Downstream: ChIPQC, vulcan
//
// Install: BiocManager::install("DiffBind")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFBIND {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-diffbind"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-diffbind:3.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-diffbind:3.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_diffbind_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_diffbind_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_diffbind_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DiffBind)
    library(jsonlite)

    # --- Normalization and Blacklist Filtering [] ---
    # Key functions: dba.blacklist, dba.normalize
    tamoxifen <- DiffBind::dba.blacklist(
        tamoxifen,
        blacklist = DiffBind::DBA_BLACKLIST_HG19,
        greylist = FALSE
    )
    tamoxifen <- DiffBind::dba.normalize(tamoxifen)


    # --- Differential Binding Analysis [] ---
    # Key functions: dba.contrast, dba.analyze, dba.report
    tamoxifen <- DiffBind::dba.contrast(
        tamoxifen,
        design = "~Tissue + Condition"
    )
    tamoxifen <- DiffBind::dba.analyze(tamoxifen)
    report <- DiffBind::dba.report(tamoxifen)


    # --- Visualization of Binding Affinity [] ---
    # Key functions: dba.plotPCA, dba.plotMA, dba.plotVolcano
    DiffBind::dba.plotPCA(tamoxifen, label = DiffBind::DBA_TISSUE)
    DiffBind::dba.plotMA(tamoxifen)
    DiffBind::dba.plotVolcano(tamoxifen)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_diffbind_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_diffbind_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_diffbind_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIFFBIND:", paste0("    diffbind: ", packageVersion("DiffBind"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diffbind_results.csv
    touch ${prefix}_diffbind_output.rds
    echo "BIOC_DIFFBIND:" > versions.yml
    echo "    diffbind: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIFFBIND_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIFFBIND(ch_input)

    emit:
    results  = BIOC_DIFFBIND.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIFFBIND.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIFFBIND.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIFFBIND.out.versions  // channel: path(versions.yml)
}
