#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: tidybulk
// This is a collection of utility functions that allow to perform exploration of and calculations to R
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/tidybulk/inst/doc/introduction.R
// Upstream  : Seurat, edgeR, limma, sva, widyr
// Downstream: none
//
// Install: BiocManager::install("tidybulk")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TIDYBULK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tidybulk"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tidybulk:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tidybulk:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tidybulk_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tidybulk_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tidybulk_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DGEList)
    library(jsonlite)

    # --- row Data [] ---
    # Key functions: rowData
    rowData(se_mini)$gene_name = rownames(se_mini)
    se_mini.aggr = se_mini |> aggregate_duplicates(.transcript = gene_name)
    # --- normalise long [] ---
    # Key functions: DGEList, filterByExpr, calcNormFactors
    library(edgeR)
    dgList <- DGEList(count_m=x,group=group)
    keep <- filterByExpr(dgList)
    # --- plot normalise [] ---
    # Key functions: ggplot, geom_density, scale_x_log10
    ggplot(aes(count_scaled + 1, group=.sample, color=`Cell.type`)) +
    geom_density() +
    scale_x_log10() +
    # --- filter variable long [] ---
    # Key functions: rowMeans
    library(edgeR)
    s <- rowMeans((x-rowMeans(x))^2)
    o <- order(s,decreasing=TRUE)
    # --- reduce_dimensions [] ---
    # Key functions: reduce_dimensions
    reduce_dimensions(method="MDS", .dims = 3)
    # --- pivot_sample [] ---
    # Key functions: pivot_sample, ggpairs
    se_mini.norm.MDS |> pivot_sample()  |> select(contains("Dim"), everything())
    pivot_sample() |>
    GGally::ggpairs(columns = 9:11, ggplot2::aes(colour=`Cell.type`))
    # --- reduce_dimensions [] ---
    # Key functions: reduce_dimensions
    reduce_dimensions(method="PCA", .dims = 3)
    # --- pivot_sample [] ---
    # Key functions: pivot_sample, ggpairs
    se_mini.norm.PCA |> pivot_sample() |> select(contains("PC"), everything())
    pivot_sample() |>
    GGally::ggpairs(columns = 11:13, ggplot2::aes(colour=`Cell.type`))
    # --- identify_abundant [] ---
    # Key functions: identify_abundant, reduce_dimensions
    identify_abundant() |>
    # --- rotate_dimensions [] ---
    # Key functions: rotate_dimensions
    rotate_dimensions(`Dim1`, `Dim2`, rotation_degrees = 45, action="get")
    # --- plot rotate 1 [] ---
    # Key functions: ggplot, geom_point
    ggplot(aes(x=`Dim1`, y=`Dim2`, color=`Cell.type` )) +
    geom_point() +
    # --- plot rotate 2 [] ---
    # Key functions: pivot_sample, ggplot, geom_point
    pivot_sample() |>
    ggplot(aes(x=`Dim1_rotated_45`, y=`Dim2_rotated_45`, color=`Cell.type` )) +
    geom_point() +
    # --- test_differential_abundance [] ---
    # Key functions: test_differential_abundance
    test_differential_abundance( ~ condition, action="get")
    # --- identify_abundant [] ---
    # Key functions: identify_abundant, test_differential_abundance
    identify_abundant(factor_of_interest = condition) |>
    # --- deconvolve_cellularity [] ---
    # Key functions: deconvolve_cellularity
    deconvolve_cellularity(action="get", cores=1, prefix = "cibersort__")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tidybulk_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tidybulk_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tidybulk_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TIDYBULK:", paste0("    tidybulk: ", packageVersion("tidybulk"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tidybulk_results.csv
    touch ${prefix}_tidybulk_output.rds
    echo "BIOC_TIDYBULK:" > versions.yml
    echo "    tidybulk: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TIDYBULK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TIDYBULK(ch_input)

    emit:
    results  = BIOC_TIDYBULK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TIDYBULK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TIDYBULK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TIDYBULK.out.versions  // channel: path(versions.yml)
}
