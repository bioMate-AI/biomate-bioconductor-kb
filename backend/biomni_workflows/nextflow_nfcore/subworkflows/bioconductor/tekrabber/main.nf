#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TEKRABber
// TEKRABber is made to provide a user-friendly pipeline for comparing orthologs and transposable eleme
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TEKRABber/inst/doc/TEKRABber.R
// Upstream  : plotly, bslib, shiny, gridlayout
// Downstream: none
//
// Install: BiocManager::install("TEKRABber")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TEKRABBER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-tekrabber"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-tekrabber:1.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-tekrabber:1.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_tekrabber_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_tekrabber_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_tekrabber_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(TEKRABber)
    library(DECorrInputs)
    library(DEgeneTE)
    library(jsonlite)

    # --- Ortholog Scaling and Normalisation ---
    # Key functions: orthologScale
    data(speciesCounts)
    data(hg38_panTro6_rmsk)
    hmGeneSample <- speciesCounts$hmGene[1:100, ]
    chimpGeneSample <- speciesCounts$chimpGene[1:100, ]
    fetchData <- orthologScale(
        speciesRef = "hsapiens",
        speciesCompare = "ptroglodytes",
        geneCountRef = hmGeneSample,
        geneCountCompare = chimpGeneSample,
        teCountRef = speciesCounts$hmTE,
        teCountCompare = speciesCounts$chimpTE,
        rmsk = hg38_panTro6_rmsk
    )

    # --- Input Preparation for DE and Correlation ---
    # Key functions: DECorrInputs
    data(fetchDataHmChimp)
    inputBundle <- DECorrInputs(fetchDataHmChimp)
    geneInputDESeq2 <- inputBundle$geneInputDESeq2
    teInputDESeq2 <- inputBundle$teInputDESeq2
    geneInputCorr <- inputBundle$geneInputCorr
    teInputCorr <- inputBundle$teInputCorr

    # --- Differential Expression Analysis ---
    # Key functions: DEgeneTE
    data(fetchDataHmChimp)
    inputBundle <- DECorrInputs(fetchDataHmChimp)
    numSamples <- ncol(inputBundle$geneInputDESeq2)
    meta <- data.frame(
        species = c(
            rep("human", numSamples / 2),
            rep("chimpanzee", numSamples / 2)
        )
    )
    meta$species <- factor(meta$species, levels = c("human", "chimpanzee"))
    rownames(meta) <- colnames(inputBundle$geneInputDESeq2)
    hmchimpDE <- DEgeneTE(
        geneTable = inputBundle$geneInputDESeq2,
        teTable = inputBundle$teInputDESeq2,
        metadata = meta,
        expDesign = TRUE
    )

    # --- Gene and TE Correlation Analysis ---
    # Key functions: corrGeneTE
    data(fetchDataHmChimp)
    inputBundle <- DECorrInputs(fetchDataHmChimp)
    hmCorrResult <- corrGeneTE(
        geneInput = inputBundle$geneInputCorr,
        teInput = inputBundle$teInputCorr,
        corrMethod = "pearson",
        padjMethod = "fdr",
        clusterNum = 2
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_tekrabber_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_tekrabber_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_tekrabber_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TEKRABBER:", paste0("    tekrabber: ", packageVersion("TEKRABber"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_tekrabber_results.csv
    touch ${prefix}_tekrabber_output.rds
    echo "BIOC_TEKRABBER:" > versions.yml
    echo "    tekrabber: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TEKRABBER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TEKRABBER(ch_input)

    emit:
    results  = BIOC_TEKRABBER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TEKRABBER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TEKRABBER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TEKRABBER.out.versions  // channel: path(versions.yml)
}
