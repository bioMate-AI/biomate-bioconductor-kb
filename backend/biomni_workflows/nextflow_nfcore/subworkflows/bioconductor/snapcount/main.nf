#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: snapcount
// snapcount is a client interface to the Snaptron webservices which support querying by gene name or g
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/snapcount/inst/doc/snapcount_vignette.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("snapcount")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SNAPCOUNT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-snapcount"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-snapcount:1.18.0--r44_0' :
        'quay.io/biocontainers/bioconductor-snapcount:1.18.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_snapcount_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_snapcount_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_snapcount_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(QueryBuilder)
    library(jsonlite)

    # --- 'install' [] ---
    # Key functions: valid
    if (!requireNamespace("BiocManager", quietly = TRUE))
    install.packages("BiocManager")
    BiocManager::install("snapcount")
    # --- 'gene' [] ---
    # Key functions: QueryBuilder
    sb <- QueryBuilder(compilation="gtex", regions="CD99")
    cd99.gene <- query_gene(sb)
    dim(cd99.gene)
    # --- 'jx2' [] ---
    # Key functions: set_column_filters
    sb <- set_column_filters(sb, SMTS == "Brain")
    cd99.jx.all <- query_jx(sb)
    dim(cd99.jx.all)
    # --- 'jx3' [] ---
    # Key functions: set_row_filters
    sb <- set_row_filters(sb, annotated == 1)
    cd99.jx <- query_jx(sb)
    dim(cd99.jx)
    # --- 'psi' [] ---
    # Key functions: QueryBuilder, set_row_filters, set_coordinate_modifier, percent_spliced_in
    lq <- QueryBuilder(compilation="gtex", regions="chr19:45297955-45298142")
    lq <- set_row_filters(lq, strand == "+")
    lq <- set_coordinate_modifier(lq, Coordinates$Exact)
    # --- 'jir' [] ---
    # Key functions: QueryBuilder, set_row_filters, set_coordinate_modifier, junction_inclusion_ratio
    A <- QueryBuilder(compilation="srav2", regions="chr2:29446395-30142858")
    A <- set_row_filters(A, strand == "-")
    A <- set_coordinate_modifier(A, Coordinates$Within)
    # --- 'ssc' [] ---
    # Key functions: QueryBuilder, set_row_filters, set_coordinate_modifier, ssc_func
    GNB1l <- QueryBuilder(compilation="gtex", regions="chr1:1879786-1879786")
    GNB1l <- set_row_filters(GNB1l, strand == "-")
    GNB1l <- set_coordinate_modifier(GNB1l, Coordinates$EndIsExactOrWithin)
    # --- 'ts1' [] ---
    # Key functions: QueryBuilder, set_row_filters, set_coordinate_modifier, tissue_specificity
    A <- QueryBuilder(compilation="gtex", regions="chr4:20763023-20763023")
    A <- set_row_filters(A, strand == "-")
    A <- set_coordinate_modifier(A, Coordinates$EndIsExactOrWithin)
    # --- 'ts2' [] ---
    # Key functions: QueryBuilder, set_row_filters, set_coordinate_modifier, tissue_specificity
    A <- QueryBuilder(compilation="gtex", regions="chr4:20763023-20763023")
    A <- set_row_filters(A, strand == "-")
    A <- set_coordinate_modifier(A, Coordinates$EndIsExactOrWithin)
    # --- 'jm' [] ---
    # Key functions: QueryBuilder, set_row_filters, set_coordinate_modifier, junction_union
    gtex <- QueryBuilder(compilation="gtex", regions="chr1:1879786-1879786")
    gtex <- set_row_filters(gtex, strand == "-")
    gtex <- set_coordinate_modifier(gtex, Coordinates$EndIsExactOrWithin)
    # --- 'ji' [] ---
    # Key functions: QueryBuilder, set_row_filters, set_coordinate_modifier, junction_intersection
    gtex <- QueryBuilder(compilation="gtex", regions="chr1:1879786-1879786")
    gtex <- set_row_filters(gtex, strand == "-")
    gtex <- set_coordinate_modifier(gtex, Coordinates$EndIsExactOrWithin)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_snapcount_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_snapcount_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_snapcount_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SNAPCOUNT:", paste0("    snapcount: ", packageVersion("snapcount"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snapcount_results.csv
    touch ${prefix}_snapcount_output.rds
    echo "BIOC_SNAPCOUNT:" > versions.yml
    echo "    snapcount: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SNAPCOUNT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SNAPCOUNT(ch_input)

    emit:
    results  = BIOC_SNAPCOUNT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SNAPCOUNT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SNAPCOUNT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SNAPCOUNT.out.versions  // channel: path(versions.yml)
}
