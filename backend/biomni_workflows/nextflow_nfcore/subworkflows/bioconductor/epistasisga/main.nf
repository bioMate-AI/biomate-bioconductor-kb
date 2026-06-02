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

    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    library(epistasisGA)
    data("case.gxe")
    case <- as.matrix(case.gxe)
    data("dad.gxe")
    # --- Rep [] ---
    # Key functions: rep
    ---------------------------------------------------------------------
    ld.block.vec <- rep(6, 4)
    # --- Data [] ---
    # Key functions: data
    ---------------------------------------------------------------------
    pp.list <- preprocess.genetic.data(case, father.genetic.data = dad,
                                       mother.genetic.data = mom,
                                       ld.block.vec = ld.block.vec,
                                       categorical.exposures = exposure)
    # --- Data [] ---
    # Key functions: islands
    ---------------------------------------------------------------------
    data(snp.annotations.mci)
    size3.combined.res <- combine.islands("size3_res", snp.annotations.mci,
                                          pp.list)
    # --- Kable [] ---
    # Key functions: kable_styling, scroll_box
    ---------------------------------------------------------------------
    library(magrittr)
    library(knitr)
    library(kableExtra)
    kable(head(size3.combined.res)) %>%
    # --- Lapply [] ---
    # Key functions: path, gadgets
    ---------------------------------------------------------------------
    #pre-process permuted data
    # --- Lapply [] ---
    # Key functions: test
    ---------------------------------------------------------------------
    # chromosome size 3 results
    # function requires a list of vectors of
    # permutation based fitness scores
    # --- Vector [] ---
    # Key functions: path, test
    ---------------------------------------------------------------------
    top.snps <- as.vector(t(size3.combined.res[1, 1:3]))
    d3.st.info <- readRDS(file.path("size3_res/null.mean.sd.info.rds"))
    d3.st.means <- d3.st.info$null.mean
    d3.st.sd <- d3.st.info$null.se

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
