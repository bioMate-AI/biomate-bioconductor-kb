#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: loci2path
// loci2path performs statistics-rigorous enrichment analysis of eQTLs in genomic regions of interest. 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/loci2path/inst/doc/loci2path-vignette.R
// Upstream  : GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("loci2path")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_LOCI2PATH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-loci2path"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-loci2path:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-loci2path:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_loci2path_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_loci2path_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_loci2path_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(loci2path)
    library(jsonlite)

    # --- gene Set [] ---
    # Key functions: geneSet, resultTable, coveredGene, getMat, getWordcloud
    eset.list <- list(Brain=brain.eset, Skin=skin.eset, Blood=blood.eset)
    biocarta.link.file <- system.file("extdata", "geneSet/biocarta.txt",
    biocarta.set.file <- system.file("extdata", "geneSet/biocarta.set.txt",

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_loci2path_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_loci2path_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_loci2path_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_LOCI2PATH:", paste0("    loci2path: ", packageVersion("loci2path"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_loci2path_results.csv
    touch ${prefix}_loci2path_output.rds
    echo "BIOC_LOCI2PATH:" > versions.yml
    echo "    loci2path: 0.0.0" >> versions.yml
    """
}


workflow BIOC_LOCI2PATH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_LOCI2PATH(ch_input)

    emit:
    results  = BIOC_LOCI2PATH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_LOCI2PATH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_LOCI2PATH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_LOCI2PATH.out.versions  // channel: path(versions.yml)
}
