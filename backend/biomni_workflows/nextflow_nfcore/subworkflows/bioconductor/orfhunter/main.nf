#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ORFhunteR
// The ORFhunteR package is a R and C++ library for an automatic determination and annotation of open r
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ORFhunteR/inst/doc/ORFhunteR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ORFhunteR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ORFHUNTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-orfhunter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-orfhunter:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-orfhunter:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_orfhunter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_orfhunter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_orfhunter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAStringSet)
    library(jsonlite)

    # --- Loadtrexper [] ---
    # Key functions: loadTrExper
    ---------------------------------------------------------------------
    seq.set <- loadTrExper(tr = trans)
    # --- Findorfs [] ---
    # Key functions: findORFs
    ---------------------------------------------------------------------
    x <- "AAAATGGCTGCGTAATGCAAAATGGCTGCGAATGCAAAATGGCTGCGAATGCCGGCACGTTGCTACGT"
    orf <- findORFs(x, codStart="ATG")
    # --- Vectorizeorfs [] ---
    # Key functions: vectorizeORFs, DNAStringSet
    ---------------------------------------------------------------------
    feats <- vectorizeORFs(x=DNAStringSet(x="ATGGGCCTCA"))
    # --- Predictorf [] ---
    # Key functions: predictORF
    ---------------------------------------------------------------------
    model <- "http://www.sstcenter.com/download/ORFhunteR/classRFmodel_1.rds"
    ORFs <- predictORF(tr = trans,
                       model= model,
                       prThr = 0)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_orfhunter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_orfhunter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_orfhunter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ORFHUNTER:", paste0("    orfhunter: ", packageVersion("ORFhunteR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_orfhunter_results.csv
    touch ${prefix}_orfhunter_output.rds
    echo "BIOC_ORFHUNTER:" > versions.yml
    echo "    orfhunter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ORFHUNTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ORFHUNTER(ch_input)

    emit:
    results  = BIOC_ORFHUNTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ORFHUNTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ORFHUNTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ORFHUNTER.out.versions  // channel: path(versions.yml)
}
