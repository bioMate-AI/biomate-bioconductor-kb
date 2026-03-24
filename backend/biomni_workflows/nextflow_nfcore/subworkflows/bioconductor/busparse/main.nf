#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BUSpaRse
// The kallisto | bustools pipeline is a fast and modular set of tools to convert single cell RNA-seq r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BUSpaRse/inst/doc/sparse-matrix.R
// Upstream  : Matrix, TENxBUSData, ggplot2, zeallot
// Downstream: none
//
// Install: BiocManager::install("BUSpaRse")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BUSPARSE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-busparse"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-busparse:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-busparse:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_busparse_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_busparse_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_busparse_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TENxBUSData)
    library(jsonlite)

    # --- Tenxbusdata [] ---
    # Key functions: TENxBUSData
    ---------------------------------------------------------------------
    TENxBUSData(".", dataset = "hgmm100")
    # --- transcript2gene [] ---
    # Key functions: transcript2gene
    ---------------------------------------------------------------------
    tr2g <- transcript2gene(species = c("Homo sapiens", "Mus musculus"), type = "vertebrate",
                            kallisto_out_path = "./out_hgmm100", ensembl_version = 99,
                            write_tr2g = FALSE)
    # --- Colsums [] ---
    # Key functions: colSums
    ---------------------------------------------------------------------
    tot_counts <- Matrix::colSums(gene_count)
    summary(tot_counts)
    # --- Get Knee Df [] ---
    # Key functions: get_knee_df, get_inflection
    ---------------------------------------------------------------------
    df1 <- get_knee_df(gene_count)
    infl1 <- get_inflection(df1)
    # --- Knee Plot [] ---
    # Key functions: knee_plot
    ---------------------------------------------------------------------
    knee_plot(df1, infl1)
    # --- Colsums [] ---
    # Key functions: colSums
    ---------------------------------------------------------------------
    tot_counts <- Matrix::colSums(tcc)
    summary(tot_counts)
    # --- Get Knee Df [] ---
    # Key functions: get_knee_df, get_inflection
    ---------------------------------------------------------------------
    df2 <- get_knee_df(tcc)
    infl2 <- get_inflection(df2)
    # --- Knee Plot [] ---
    # Key functions: knee_plot
    ---------------------------------------------------------------------
    knee_plot(df2, infl2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_busparse_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_busparse_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_busparse_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BUSPARSE:", paste0("    busparse: ", packageVersion("BUSpaRse"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_busparse_results.csv
    touch ${prefix}_busparse_output.rds
    echo "BIOC_BUSPARSE:" > versions.yml
    echo "    busparse: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BUSPARSE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BUSPARSE(ch_input)

    emit:
    results  = BIOC_BUSPARSE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BUSPARSE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BUSPARSE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BUSPARSE.out.versions  // channel: path(versions.yml)
}
