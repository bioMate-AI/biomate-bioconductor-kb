#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pmm
// The Parallel Mixed Model (PMM) approach is suitable for hit selection and cross-comparison of RNAi s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pmm/inst/doc/pmm-package.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("pmm")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PMM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pmm"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pmm:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pmm:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pmm_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pmm_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pmm_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pmm)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(pmm)
    data(kinome)
    head(kinome)
    # --- pmm [] ---
    # Key functions: pmm
    fit1 <- pmm(kinome, "InfectionIndex", gene.col = "GeneName",
    condition.col = "condition")
    head(fit1)
    # --- Plotex1 [] ---
    # Key functions: hitheatmap
    hitheatmap(fit1, threshold = 0.2)
    # --- Pmm Package.Rnw:202 203 [] ---
    # Key functions: hitheatmap
    hitheatmap(fit1, threshold = 0.2)
    # --- Plotex2 [] ---
    # Key functions: hitheatmap
    hitheatmap(fit1, threshold = 0.4, cex.main = 2,
    main = "My modified plot", col.main = "white",
    col.axis = "white", cex.axis = 0.8, bg = "black", mar = c(6,8,4,6))
    # --- Pmm Package.Rnw:227 228 [] ---
    # Key functions: hitheatmap
    hitheatmap(fit1, threshold = 0.4, cex.main = 2,
    main = "My modified plot", col.main = "white",
    col.axis = "white", cex.axis = 0.8, bg = "black", mar = c(6,8,4,6))
    # --- sharedness [] ---
    # Key functions: sharedness
    sh <- sharedness(fit1, threshold = 0.2)
    sh[order(sh$Sharedness),]
    # --- Plotex3 [] ---
    # Key functions: hitheatmap
    hitheatmap(fit1, sharedness.score = TRUE, main = "My hits found by PMM")
    # --- Pmm Package.Rnw:262 263 [] ---
    # Key functions: hitheatmap
    hitheatmap(fit1, sharedness.score = TRUE, main = "My hits found by PMM")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pmm_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pmm_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pmm_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PMM:", paste0("    pmm: ", packageVersion("pmm"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pmm_results.csv
    touch ${prefix}_pmm_output.rds
    echo "BIOC_PMM:" > versions.yml
    echo "    pmm: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PMM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PMM(ch_input)

    emit:
    results  = BIOC_PMM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PMM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PMM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PMM.out.versions  // channel: path(versions.yml)
}
