#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GDSArray
// GDS files are widely used to represent genotyping or sequence data. The GDSArray package implements 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GDSArray/inst/doc/GDSArray.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GDSArray")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GDSARRAY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gdsarray"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gdsarray:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gdsarray:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gdsarray_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gdsarray_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gdsarray_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GDSArray)
    library(jsonlite)

    # --- gds Example File Name [] ---
    # Key functions: gdsExampleFileName, GDSArray
    file <- gdsExampleFileName("seqgds")
    GDSArray(file, "genotype/data")
    # --- G D S Array [] ---
    # Key functions: GDSArray
    GDSArray(file, "annotation/format/DP/data")
    # --- gdsnodes [] ---
    # Key functions: gdsnodes, GDSArray
    gdsnodes(file)
    identical(gdsnodes(file), gdsnodes(gf))
    varname <- gdsnodes(file)[2]
    # --- G D S Array [] ---
    # Key functions: GDSArray, lengths
    dp <- GDSArray(file, "annotation/format/DP/data")
    dim(dp)
    class(dimnames(dp))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gdsarray_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gdsarray_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gdsarray_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GDSARRAY:", paste0("    gdsarray: ", packageVersion("GDSArray"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gdsarray_results.csv
    touch ${prefix}_gdsarray_output.rds
    echo "BIOC_GDSARRAY:" > versions.yml
    echo "    gdsarray: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GDSARRAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GDSARRAY(ch_input)

    emit:
    results  = BIOC_GDSARRAY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GDSARRAY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GDSARRAY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GDSARRAY.out.versions  // channel: path(versions.yml)
}
