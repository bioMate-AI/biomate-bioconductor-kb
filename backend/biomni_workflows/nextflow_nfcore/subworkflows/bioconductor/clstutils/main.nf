#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: clstutils
// Tools for performing taxonomic assignment based on phylogeny using pplacer and clst.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/clstutils/inst/doc/pplacerDemo.R
// Upstream  : ape, clst, lattice
// Downstream: none
//
// Install: BiocManager::install("clstutils")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLSTUTILS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-clstutils"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-clstutils:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-clstutils:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_clstutils_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_clstutils_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_clstutils_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(clstutils)
    library(jsonlite)

    # --- Create [] ---
    # Key functions: create
    figdir <- 'figs'
      dir.create(figdir, showWarnings=FALSE)
    # --- Treedists [] ---
    # Key functions: treeDists
    treedists <- treeDists(distfile=distfile, placefile=placefile)
    # --- Taxonomyfromrefpkg [] ---
    # Key functions: taxonomyFromRefpkg
    taxdata <- taxonomyFromRefpkg(refpkg, seqnames=rownames(treedists$dmat), lowest_rank='species')
    # --- Frame [] ---
    # Key functions: frame
    placetab <- data.frame(at=49, edge=5.14909e-07, branch=5.14909e-07)
    # --- Classifyplacements [] ---
    # Key functions: classifyPlacements
    cdata <- classifyPlacements(taxdata, treedists, placetab)
    cdata

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_clstutils_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_clstutils_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_clstutils_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLSTUTILS:", paste0("    clstutils: ", packageVersion("clstutils"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_clstutils_results.csv
    touch ${prefix}_clstutils_output.rds
    echo "BIOC_CLSTUTILS:" > versions.yml
    echo "    clstutils: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLSTUTILS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLSTUTILS(ch_input)

    emit:
    results  = BIOC_CLSTUTILS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLSTUTILS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLSTUTILS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLSTUTILS.out.versions  // channel: path(versions.yml)
}
