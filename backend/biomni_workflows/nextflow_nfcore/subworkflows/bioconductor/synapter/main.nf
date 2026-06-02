#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: synapter
// The synapter package provides functionality to reanalyse label-free proteomics data acquired on a Sy
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/synapter/inst/doc/fragmentmatching.R
// Upstream  : BiocManager, BiocStyle, qvalue, synapterdata
// Downstream: synapterdata
//
// Install: BiocManager::install("synapter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNAPTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-synapter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-synapter:2.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-synapter:2.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_synapter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_synapter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_synapter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(synapter)
    library(jsonlite)


    # --- Environment [] ---
    # Key functions: suppressPackageStartupMessages, synobj2RData, synapter, synapterdata, readLines, scripts, create_synobj2.R
    suppressPackageStartupMessages(library("synapter"))
    suppressPackageStartupMessages(library("synapterdata"))
    suppressPackageStartupMessages(library("BiocStyle"))
    synobj2RData()
    #  library("synapterdata")
    #  synobj2RData()

    ## ----create-synobj2-file, echo=FALSE, comment=NA------------------------------
    cat(readLines(system.file(file.path("scripts", "create_synobj2.R"),
                              package="synapterdata"), n=13), sep="\n")

    # --- Create Synobj2 [] ---
    # Key functions: synergise1, tempdir, plotCumulativeNumberOfFragments, fragments.ident, spectra.quant
    synobj2 <- synergise1(object=synobj2,
                          outputdir=tempdir())
    plotCumulativeNumberOfFragments(synobj2,
                                    what = "fragments.ident")
    plotCumulativeNumberOfFragments(synobj2,
                                    what = "spectra.quant")

    # --- Filterfragments [] ---
    # Key functions: filterFragments, fragments.ident, spectra.quant, setFragmentMatchingPpmTolerance, fragmentMatching
    filterFragments(synobj2,
                    what = "fragments.ident",
                    minIntensity = 70)
    filterFragments(synobj2,
                    what = "spectra.quant",
                    minIntensity = 70)
    setFragmentMatchingPpmTolerance(synobj2, 25)
    fragmentMatching(synobj2)

    # --- Plotfm22 [] ---
    # Key functions: plotFragmentMatching, peptide.seq
    plotFragmentMatching(synobj2,
                         key = 28,
                         column = "FragmentMatching")
    plotFragmentMatching(synobj2,
                         key = "TALIDGLAQR",
                         column = "peptide.seq")

    # --- Plotfmid [] ---
    # Key functions: plotFragmentMatching, precursor.leID.ident, plotFragmentMatchingPerformance
    plotFragmentMatching(synobj2,
                         key = 12589,
                         column = "precursor.leID.ident")
    m <- plotFragmentMatchingPerformance(synobj2)

    # --- Confusionmatrixunique [] ---
    # Key functions: synapter
    knitr::kable(m$unique[1:15,], row.names=FALSE,
                 caption="Number of true positives, false negatives, false positives, false negatives and false discovery rate for a given number of common peaks.")
    knitr::kable(m$nonunique[1:15,], row.names=FALSE,
                 caption="Number of true positives, false negatives, false positives, false negatives and false discovery rate for a given difference in number of common peaks between the higest and second highest multiply matching EMRTs in terms of number of common peptides.")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_synapter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_synapter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_synapter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYNAPTER:", paste0("    synapter: ", packageVersion("synapter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synapter_results.csv
    touch ${prefix}_synapter_output.rds
    echo "BIOC_SYNAPTER:" > versions.yml
    echo "    synapter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYNAPTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYNAPTER(ch_input)

    emit:
    results  = BIOC_SYNAPTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYNAPTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYNAPTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYNAPTER.out.versions  // channel: path(versions.yml)
}
