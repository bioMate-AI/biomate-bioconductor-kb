#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: mina
// An increasing number of microbiome datasets have been generated and analyzed with the help of rapidl
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/mina/inst/doc/mina.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("mina")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MINA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mina"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mina:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mina:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mina_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mina_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mina_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(mina)
    library(jsonlite)

    # --- Community Dissimilarity and Variance Analysis [] ---
    # Key functions: com_dis, com_r2, get_r2, dis
    maize <- fit_tabs(maize)
    maize <- com_dis(maize, method = "bray")
    r2_res <- com_r2(
        maize,
        group = c("Compartment", "Soil", "Host_genotype")
    )
    maize_dis <- dis(maize)
    r2_manual <- get_r2(
        maize_dis,
        maize_des2,
        group = c("Compartment", "Soil")
    )


    # --- Dimensionality Reduction and Visualization [] ---
    # Key functions: dmr, com_plot, pcoa_plot
    maize <- dmr(maize)
    p1 <- com_plot(maize, match = "Sample_ID", color = "Compartment")
    p2 <- com_plot(
        maize, match = "Sample_ID", d1 = 3, d2 = 4,
        color = "Compartment"
    )
    maize_dmr <- dmr(maize_dis, k = 4)
    p3 <- pcoa_plot(
        maize_dmr, maize_des2, match = "Sample_ID",
        d1 = 3, d2 = 4, color = "Host_genotype"
    )


    # --- Network Adjacency and Clustering [] ---
    # Key functions: adj, net_cls, net_cls_tab, cls_tab, com_dis
    maize <- adj(maize, method = "spearman", sig = TRUE)
    maize <- net_cls(maize, method = "mcl", cutoff = 0.6)
    maize <- net_cls_tab(maize)
    maize_cls_tab <- cls_tab(maize)
    maize_cls_dis <- com_dis(maize_cls_tab, method = "bray")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mina_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mina_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mina_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MINA:", paste0("    mina: ", packageVersion("mina"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mina_results.csv
    touch ${prefix}_mina_output.rds
    echo "BIOC_MINA:" > versions.yml
    echo "    mina: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MINA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MINA(ch_input)

    emit:
    results  = BIOC_MINA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MINA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MINA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MINA.out.versions  // channel: path(versions.yml)
}
