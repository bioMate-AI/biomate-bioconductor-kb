#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nucleoSim
// This package can generate a synthetic map with reads covering the nucleosome regions as well as a sy
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nucleoSim/inst/doc/nucleoSim.R
// Upstream  : knitr
// Downstream: none
//
// Install: BiocManager::install("nucleoSim")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NUCLEOSIM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nucleosim"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nucleosim:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nucleosim:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nucleosim_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nucleosim_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nucleosim_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(nucleoSim)
    library(jsonlite)

    # --- synthetic Nuc Map From Dist [] ---
    # Key functions: syntheticNucMapFromDist
    nuc.len          <- 147        ### Length of the nucleosome (default: 147)
    lin.len          <- 20         ### Length of the DNA linker (default: 20)
    nucleosomeMap <- syntheticNucMapFromDist(wp.num=wp.num, wp.del=wp.del,
    # --- synthetic Nuc Reads From Dist [] ---
    # Key functions: syntheticNucReadsFromDist
    nuc.len          <- 147           ### Length of the nucleosome (default: 147)
    lin.len          <- 20            ### Length of the DNA linker (default: 20)
    nucleosomeSample <- syntheticNucReadsFromDist(wp.num=wp.num, wp.del=wp.del,
    # --- synthetic Nuc Reads From Map [] ---
    # Key functions: syntheticNucReadsFromMap
    class(nucleosomeMap)
    nucleosomeSampleFromMap <- syntheticNucReadsFromMap(nucleosomeMap,
    head(nucleosomeSampleFromMap$dataIP, n = 2)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nucleosim_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nucleosim_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nucleosim_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NUCLEOSIM:", paste0("    nucleosim: ", packageVersion("nucleoSim"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nucleosim_results.csv
    touch ${prefix}_nucleosim_output.rds
    echo "BIOC_NUCLEOSIM:" > versions.yml
    echo "    nucleosim: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NUCLEOSIM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NUCLEOSIM(ch_input)

    emit:
    results  = BIOC_NUCLEOSIM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NUCLEOSIM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NUCLEOSIM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NUCLEOSIM.out.versions  // channel: path(versions.yml)
}
