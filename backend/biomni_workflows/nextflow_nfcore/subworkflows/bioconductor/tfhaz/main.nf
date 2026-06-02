#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TFHAZ
// It finds trascription factor (TF) high accumulation DNA zones, i.e., regions along the genome where 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TFHAZ/inst/doc/TFHAZ.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("TFHAZ")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TFHAZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tfhaz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tfhaz:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tfhaz:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tfhaz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tfhaz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tfhaz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TFHAZ)
    library(jsonlite)


    # --- Include=false [] ---
    # Key functions: data_man
    library(TFHAZ)
    library(GenomicRanges)
    library(IRanges)
    library(S4Vectors)
    data("data_man")

    ## -----------------------------------------------------------------------------
    # load and visualize the dataset:
    data("Ishikawa")
    dim(as.data.frame(Ishikawa))
    head(Ishikawa)


    ## -----------------------------------------------------------------------------
    # calculate TF accumulation for the chromosome 21 for w=0

    # --- PCA [] ---
    # Key functions: function, n_zones_PCA, chr21, reg, base
    # TF_dense_21_w_10 is the output of dense_zones function applied to the
    # accumulation vector found with w=10, chr="chr21", acctype="TF".
    # reg_dense_21_w_10 is the output of dense_zones function applied to the
    # accumulation vector found with w=10, chr="chr21", acctype="reg".   
    # base_dense_21_w_10 is the output of dense_zones function (with 
    # threshold_step=21 in order to have 14 threshold values as in the other two
    # inputs) applied to the accumulation vector found with w=10, chr="chr21",
    # acctype="base".
    # PCA
    n_zones_PCA(TF_dense_w_10, reg_dense_w_10, base_dense_w_10, chr = "chr21")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tfhaz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tfhaz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tfhaz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TFHAZ:", paste0("    tfhaz: ", packageVersion("TFHAZ"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tfhaz_results.csv
    touch ${prefix}_tfhaz_output.rds
    echo "BIOC_TFHAZ:" > versions.yml
    echo "    tfhaz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TFHAZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TFHAZ(ch_input)

    emit:
    results  = BIOC_TFHAZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TFHAZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TFHAZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TFHAZ.out.versions  // channel: path(versions.yml)
}
