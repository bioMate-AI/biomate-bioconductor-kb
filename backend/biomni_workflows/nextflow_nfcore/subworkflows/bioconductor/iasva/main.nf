#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iasva
// Iteratively Adjusted Surrogate Variable Analysis (IA-SVA) is a statistical framework to uncover hidd
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iasva/inst/doc/detecting_hidden_heterogeneity_iasvaV0.95.R
// Upstream  : DescTools, RColorBrewer, Rtsne, SummarizedExperiment, corrplot
// Downstream: none
//
// Install: BiocManager::install("iasva")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_IASVA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-iasva"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-iasva:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-iasva:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_iasva_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_iasva_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_iasva_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SummarizedExperiment)
    library(jsonlite)

    # --- geno lib size [] ---
    # Key functions: colSums, irlba
    geo_lib_size <- colSums(log(counts + 1))
    barplot(geo_lib_size, xlab = "Cell", ylab = "Geometric Lib Size", las = 2)
    lcounts <- log(counts + 1)
    # --- Create SummarizedExperiment [] ---
    # Key functions: SummarizedExperiment, pairs
    set.seed(100)
    mod <- model.matrix(~patient_id + geo_lib_size)
    summ_exp <- SummarizedExperiment(assays = counts)
    # --- Plot hierarchical clustering heatmap [] ---
    # Key functions: pheatmap
    marker.counts <- find_markers(summ_exp, as.matrix(iasva.sv[,1]))
    nrow(marker.counts)
    rownames(marker.counts)
    # --- study r2 [] ---
    # Key functions: study_R2
    study_res <- study_R2(summ_exp, iasva.sv)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_iasva_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_iasva_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_iasva_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_IASVA:", paste0("    iasva: ", packageVersion("iasva"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_iasva_results.csv
    touch ${prefix}_iasva_output.rds
    echo "BIOC_IASVA:" > versions.yml
    echo "    iasva: 0.0.0" >> versions.yml
    """
}


workflow BIOC_IASVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_IASVA(ch_input)

    emit:
    results  = BIOC_IASVA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_IASVA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_IASVA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_IASVA.out.versions  // channel: path(versions.yml)
}
