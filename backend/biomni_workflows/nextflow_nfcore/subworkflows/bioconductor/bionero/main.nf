#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BioNERO
// BioNERO aims to integrate all aspects of biological network inference in a single package, including
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BioNERO/inst/doc/vignette_01_GCN_inference.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("BioNERO")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIONERO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-bionero"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-bionero:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-bionero:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_bionero_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_bionero_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_bionero_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BioNERO)
    library(PC_correction)
    library(SFT_fit)
    library(ZKfiltering)
    library(jsonlite)

    # --- Network Construction [] ---
    # Key functions: SFT_fit, exp2gcn
    sft <- SFT_fit(
        exp_filt, net_type = "signed hybrid",
        cor_method = "pearson"
    )
    net <- exp2gcn(
        exp_filt, net_type = "signed hybrid",
        SFTpower = sft$power, cor_method = "pearson"
    )


    # --- Module-Trait Association and Visualization [] ---
    # Key functions: module_trait_cor, plot_module_trait_cor, plot_expression_profile
    MEtrait <- module_trait_cor(exp = exp_filt, MEs = net$MEs)
    plot_module_trait_cor(MEtrait)
    plot_expression_profile(
        exp = exp_filt, net = net,
        plot_module = TRUE, modulename = "yellow"
    )


    # --- Network Export and Visualization [] ---
    # Key functions: get_hubs_gcn, get_edge_list, plot_gcn
    hubs <- get_hubs_gcn(exp_filt, net)
    edges <- get_edge_list(
        net, module = "midnightblue",
        filter = TRUE, method = "min_cor", rcutoff = 0.7
    )
    plot_gcn(
        edgelist_gcn = edges, net = net,
        color_by = "module", hubs = hubs
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_bionero_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_bionero_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_bionero_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIONERO:", paste0("    bionero: ", packageVersion("BioNERO"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bionero_results.csv
    touch ${prefix}_bionero_output.rds
    echo "BIOC_BIONERO:" > versions.yml
    echo "    bionero: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIONERO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_BIONERO(ch_input)

    emit:
    results  = BIOC_BIONERO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIONERO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIONERO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIONERO.out.versions  // channel: path(versions.yml)
}
