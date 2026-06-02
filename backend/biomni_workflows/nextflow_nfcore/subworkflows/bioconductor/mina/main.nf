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


    # --- Import Data [] ---
    # Key functions: new, mina
    library(mina)
        # maize_asv2 and maize_des2 are subset of maize_asv and maize_des
        maize <- new("mina", tab = maize_asv2, des = maize_des2)
    head(maize_des)

    # --- Show Data 2 [] ---
    # Key functions: fit_tabs
    maize_asv[1:6, 1:6]
    maize <- fit_tabs(maize)

    # --- Raref Data [] ---
    # Key functions: norm_tab, total, raref
    # check available normalization methods
        ? norm_tab_method_list
        # normalized by total sum
        maize <- norm_tab(maize, method = "total")
        # normalized by rarefaction
        maize <- norm_tab(maize, method = "raref", depth = 5000)
        # normalized by rarefaction and bootstrap 9 times
        maize <- norm_tab(maize, method = "raref", depth = 5000, multi = 9)
    # normalized by total sum
        maize_asv_norm <- norm_tab(maize_asv2, method = "total")
        # normalized by rarefaction
        maize_asv_norm <- norm_tab(maize_asv2, method = "raref", depth = 5000)
        # normalized by rarefaction and bootstrap 99 times
        maize_asv_norm <- norm_tab(maize_asv2, method = "raref", depth = 5000,
                                   multi = 9)

    # --- Com Dis [] ---
    # Key functions: fit_tabs, com_dis, bray, tina, com_r2, dis, get_r2, Host_genotype
    # check available dissimilarity parameters
        ? com_dis_list
        # tidy the norm tab, intial tab and des tab
        maize <- fit_tabs(maize)
        # community dissimilarity calculation, Bray-Curtis used in example
        maize <- com_dis(maize, method = "bray")
        # TINA dissimilarity in Schmidt_et_al_2016
        # maize <- com_dis(maize, method = "tina")
    # get the unexplained variance ratio of quantitative table according to the
        # group information indicated in descriptive table.
        com_r2(maize, group = c("Compartment", "Soil", "Host_genotype"))
        # use tables as input
        maize_dis <- dis(maize)
        get_r2(maize_dis, maize_des, group = c("Compartment", "Soil", "Host_genotype"))

    # --- Pcoa [] ---
    # Key functions: dmr, com_plot, Sample_ID, pcoa_plot, Host_genotype
    # dimensionality reduction
        maize <- dmr(maize)
        # plot the community beta-diversity
        # separate samples from different conditions by color, plot PCo1 and PCo2
        p1 <- com_plot(maize, match = "Sample_ID", color = "Compartment")
        # plot PCo3 and PCo4
        p2 <- com_plot(maize, match = "Sample_ID", d1 = 3, d2 = 4, color =
                        "Compartment")
        # in addition, separate samples from different soil type by shape
    # --- Adj [] ---
    # Key functions: adj, pearson, spearman
    # check available adjacency matrix
        ? adj_method_list
        # Pearson and Spearman correlation
        maize <- adj(maize, method = "pearson")
        # Pearson and Spearman correlation with significance test
        maize <- adj(maize, method = "spearman", sig = TRUE)
    # Pearson and Spearman correlation
        asv_adj <- adj(maize_asv_norm, method = "pearson")

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
