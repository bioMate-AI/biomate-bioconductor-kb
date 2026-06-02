#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: epistasisGA
// This package runs the GADGETS method to identify epistatic effects in nuclear family studies. It als
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/epistasisGA/inst/doc/E_GADGETS.R
// Upstream  : BiocParallel, ggplot2, grid, kableExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("epistasisGA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_EPISTASISGA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-epistasisga"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-epistasisga:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-epistasisga:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_epistasisga_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_epistasisga_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_epistasisga_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(epistasisGA)
    library(jsonlite)

    # --- Genetic Algorithm Execution [] ---
    # Key functions: run.gadgets
    run.gadgets(
        pp.list, n.chromosomes = 5, chromosome.size = 3,
        results.dir = "size3_res", cluster.type = "interactive",
        registryargs = list(file.dir = "size3_reg", seed = 1300),
        n.islands = 8, island.cluster.size = 4,
        n.migrations = 2
    )


    # --- Island Combination and Permutation [] ---
    # Key functions: combine.islands, permute.dataset
    size3.combined.res <- combine.islands(
        "size3_res",
        snp.annotations.mci,
        pp.list
    )
    permute.dataset(
        pp.list,
        permutation.data.file.path = "perm_data",
        n.permutations = 4
    )


    # --- Global and GxE Testing [] ---
    # Key functions: global.test, GxE.test
    global.test.res <- global.test(final.results, n.top.scores = 1)
    GxE.test.res <- GxE.test(
        top.snps,
        pp.list,
        null.mean.vec = d3.st.means,
        null.sd.vec = d3.st.sd
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_epistasisga_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_epistasisga_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_epistasisga_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_EPISTASISGA:", paste0("    epistasisga: ", packageVersion("epistasisGA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_epistasisga_results.csv
    touch ${prefix}_epistasisga_output.rds
    echo "BIOC_EPISTASISGA:" > versions.yml
    echo "    epistasisga: 0.0.0" >> versions.yml
    """
}


workflow BIOC_EPISTASISGA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_EPISTASISGA(ch_input)

    emit:
    results  = BIOC_EPISTASISGA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_EPISTASISGA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_EPISTASISGA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_EPISTASISGA.out.versions  // channel: path(versions.yml)
}
