#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiCExperiment
// R generic interface to Hi-C contact matrices in `.(m)cool`, `.hic` or HiC-Pro derived formats, as we
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiCExperiment/inst/doc/HiCExperiment.R
// Upstream  : GenomicRanges, HiContactsData, dplyr
// Downstream: HiContacts, HiCool, DNAZooData
//
// Install: BiocManager::install("HiCExperiment")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICEXPERIMENT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicexperiment"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicexperiment:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicexperiment:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicexperiment_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicexperiment_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicexperiment_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CoolFile)
    library(HiContactsData)
    library(HicFile)
    library(HicproFile)
    library(jsonlite)

    # --- Import genomic data file [] ---
    # Key functions: HiContactsData, import, CoolFile, HicFile, HicproFile, availableChromosomes, focus, availableResolutions
    pairs_file <- HiContactsData('yeast_wt', format = 'pairs.gz')
    coolf <- CoolFile(cool_file, pairsFile = pairs_file)
    import(coolf)
    # --- Sequence information check [] ---
    # Key functions: showClass, contacts_yeast, include_graphics, fileName, focus, resolutions, resolution, interactions
    seqinfo(hic) ## To recover the `Seqinfo` object from the `.(m)cool` file
    bins(hic) ## To bin the genome at the current resolution
    regions(hic) ## To extract unique regions of the contact matrix

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicexperiment_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicexperiment_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicexperiment_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICEXPERIMENT:", paste0("    hicexperiment: ", packageVersion("HiCExperiment"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicexperiment_results.csv
    touch ${prefix}_hicexperiment_output.rds
    echo "BIOC_HICEXPERIMENT:" > versions.yml
    echo "    hicexperiment: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICEXPERIMENT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICEXPERIMENT(ch_input)

    emit:
    results  = BIOC_HICEXPERIMENT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICEXPERIMENT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICEXPERIMENT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICEXPERIMENT.out.versions  // channel: path(versions.yml)
}
