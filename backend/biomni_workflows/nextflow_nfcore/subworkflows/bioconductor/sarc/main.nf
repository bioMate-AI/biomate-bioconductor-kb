#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SARC
// Imports a cov/coverage file (normalised read coverages from BAM files) and a cnv file (list of CNVs 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SARC/inst/doc/SARC_guide.R
// Upstream  : GenomicAlignments, ggplot2, kableExtra, knitr
// Downstream: none
//
// Install: BiocManager::install("SARC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SARC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sarc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sarc:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sarc:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sarc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sarc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sarc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(SARC)
    library(TxDb)
    library(jsonlite)

    # --- Coverage Mean and Quantile Calculation [] ---
    # Key functions: regionMean, regionQuantiles
    SARC <- regionMean(
        RE = SARC,
        cnv = test_cnv,
        splitcov = metadata(SARC)[[4]]
    )
    SARC <- regionQuantiles(
        RE = SARC,
        cnv = metadata(SARC)[["CNVlist"]][[2]],
        meancov = metadata(SARC)[[5]],
        q1 = 0.1,
        q2 = 0.9
    )


    # --- Statistical Rarity Analysis [] ---
    # Key functions: prepAnova, anovaOnCNV
    SARC <- prepAnova(
        RE = SARC,
        start = metadata(SARC)[[2]],
        end = metadata(SARC)[[3]],
        cnv = metadata(SARC)[["CNVlist"]][[3]]
    )
    SARC <- anovaOnCNV(
        RE = SARC,
        cnv = metadata(SARC)[["CNVlist"]][[3]],
        anovacov = metadata(SARC)[[8]]
    )


    # --- Genomic Annotation and Plot Setup [] ---
    # Key functions: plotCovPrep, regionGrangeMake, addExonsGenes, setupCNVplot
    SARC <- plotCovPrep(
        RE = SARC,
        cnv = metadata(SARC)[["CNVlist"]][[4]],
        startlist = metadata(SARC)[[2]],
        endlist = metadata(SARC)[[3]],
        n1 = 0,
        n2 = 0
    )
    SARC <- regionGrangeMake(RE = SARC, covprepped = metadata(SARC)[[9]])
    SARC <- addExonsGenes(
        RE = SARC,
        covgranges = metadata(SARC)[[10]],
        txdb = txdb,
        txgene = txgene
    )
    SARC <- setupCNVplot(
        RE = SARC,
        namedgranges = metadata(SARC)[[11]],
        covprepped = metadata(SARC)[[9]]
    )


    # --- CNV Confidence and Visualization [] ---
    # Key functions: cnvConfidence, plotCNV, setQDplot, seeDist
    SARC <- cnvConfidence(RE = SARC, cnv = metadata(SARC)[["CNVlist"]][[4]])
    plotCNV(
        cnv = metadata(SARC)[["CNVlist"]][[4]],
        setup = metadata(SARC)[[12]],
        FilteredCNV = 1
    )
    SARC <- setQDplot(RE = SARC, meancov = metadata(SARC)[[5]])
    seeDist(
        meanList = metadata(SARC)[[13]],
        cnv = metadata(SARC)[["CNVlist"]][[5]],
        sample = 1,
        plotly = FALSE
    )


    # --- Exon and Gene Annotation Merging [] ---
    # Key functions: pasteExonsGenes
    SARC <- pasteExonsGenes(
        RE = SARC,
        setup = metadata(SARC)[[12]],
        cnv = metadata(SARC)[["CNVlist"]][[5]]
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sarc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sarc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sarc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SARC:", paste0("    sarc: ", packageVersion("SARC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sarc_results.csv
    touch ${prefix}_sarc_output.rds
    echo "BIOC_SARC:" > versions.yml
    echo "    sarc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SARC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SARC(ch_input)

    emit:
    results  = BIOC_SARC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SARC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SARC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SARC.out.versions  // channel: path(versions.yml)
}
