#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: escheR
// The creation of effective visualizations is a fundamental component of data analysis. In biomedical 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/escheR/inst/doc/SRT_eg.R
// Upstream  : devtools, ggpubr, STexampleData, scater, scran
// Downstream: none
//
// Install: BiocManager::install("escheR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ESCHER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-escher"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-escher:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-escher:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(singlecellexperiment)

    output:
    tuple val(meta), path("${meta.id}_escher_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_escher_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_escher_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(escheR)
    library(jsonlite)


    # --- Include = False [] ---
    # Key functions: set, Visium_humanDLPFC
    knitr::opts_chunk$set(
      collapse = TRUE,
      message = FALSE,
      comment = "#>",
      # fig.width = 8,
      # fig.height = 8,
      fig.small = TRUE,
      fig.retina = NULL
    )
    spe <- Visium_humanDLPFC()

    # Subset in-tissue spots
    spe <- spe[, spe$in_tissue == 1]
    spe <- spe[, !is.na(spe$ground_truth)]

    # --- Spe Summary [] ---
    # Key functions: make_escheR
    spe
    p <- make_escheR(spe)

    # --- Creat Fill [] ---
    # Key functions: add_fill, cell_count, add_ground, ground_truth
    (p1 <- p |>
       add_fill(var = "cell_count"))
    (p2 <- p |>
       add_ground(var = "ground_truth")) # round layer

    # --- Add Symbol [] ---
    # Key functions: add_symbol, ground_truth, counts, rowData, make_escheR, add_fill, add_ground, counts_MOBP
    p2 |>
      add_symbol(var = "ground_truth", size = 0.2) # Symbol layer
    # Prep data
    # Adding gene counts for MBP to the colData
    spe$counts_MOBP <- counts(spe)[which(rowData(spe)$gene_name=="MOBP"),]

    (p <- make_escheR(spe) |> 
        add_fill(var = "counts_MOBP") |> 
        add_ground(var = "ground_truth", stroke = 0.5))

    # --- Improved Con Cat Eg [] ---
    # Key functions: scale_fill_gradient, white, black, cut, fivenum
    (p2 <- p + 
       scale_fill_gradient(low = "white", high = "black"))
    spe$tmp_group <- cut(
      spe$array_row, 
      breaks = c(min(spe$array_row)-1 ,
                 fivenum(spe$array_row))
    )

    table(spe$tmp_group)

    # --- Cat Cat Eg [] ---
    # Key functions: make_escheR, add_fill, add_ground, scale_fill_brewer, theme_void, tmp_group, ground_truth, transparent
    make_escheR(spe) |> 
      add_fill(var = "tmp_group") |> 
      add_ground(var = "ground_truth", stroke = 0.5) +
      scale_fill_brewer() +
      theme_void()
    make_escheR(spe) |> 
      add_fill(var = "tmp_group") |> 
      add_ground(var = "ground_truth", stroke = 0.5) +
      scale_fill_brewer() +

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_escher_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_escher_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_escher_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ESCHER:", paste0("    escher: ", packageVersion("escheR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_escher_results.csv
    touch ${prefix}_escher_output.rds
    echo "BIOC_ESCHER:" > versions.yml
    echo "    escher: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ESCHER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(singlecellexperiment) ]

    main:
    BIOC_ESCHER(ch_input)

    emit:
    results  = BIOC_ESCHER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ESCHER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ESCHER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ESCHER.out.versions  // channel: path(versions.yml)
}
