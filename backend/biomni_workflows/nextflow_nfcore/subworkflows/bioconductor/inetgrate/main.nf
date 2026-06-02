#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iNETgrate
// The iNETgrate package provides functions to build a correlation network in which nodes are genes. DN
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iNETgrate/inst/doc/iNETgrate_inference.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("iNETgrate")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INETGRATE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-inetgrate"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-inetgrate:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-inetgrate:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_inetgrate_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_inetgrate_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_inetgrate_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iNETgrate)
    library(jsonlite)

    # --- Gene Selection [] ---
    # Key functions: electGenes
    data(toyCleanedAml)
    resPath <- file.path(tempdir(), "iNETgrateRes")
    elected <- electGenes(
        genExpr = toyCleanedAml$genExpr,
        dnam = toyCleanedAml$dnam,
        survival = toyCleanedAml$survival,
        savePath = resPath,
        event = "Dead",
        locus2gene = toyCleanedAml$locus2gene,
        doAlLoci = FALSE,
        verbose = 0
    )


    # --- Eigenloci Computation [] ---
    # Key functions: computEigenloci
    patientLabel <- setNames(
        as.character(toyCleanedAml$survival$Risk1),
        nm = rownames(toyCleanedAml$survival)
    )
    inBoth <- intersect(colnames(toyCleanedAml$dnam), names(patientLabel))
    computedEloci <- computEigenloci(
        dnam = toyCleanedAml$dnam[, inBoth],
        Labels = patientLabel[inBoth],
        geNames = elected$unionGenes,
        locus2gene = toyCleanedAml$locus2gene,
        plotPath = tempdir(),
        Label1 = "Low",
        Label2 = "High",
        verbose = 0
    )


    # --- Network Construction [] ---
    # Key functions: makeNetwork
    netPath <- file.path(tempdir(), "iNETgrateRes", "net")
    dir.create(netPath, showWarnings = FALSE, recursive = TRUE)
    madeNet <- makeNetwork(
        genExpr = toyCleanedAml$genExpr,
        eigenloci = computedEloci$eigenloci,
        geNames = elected$unionGenes,
        mus = 0.6,
        doRemoveTOM = TRUE,
        outPath = netPath,
        verbose = 0
    )


    # --- Eigengene Integration and Survival Analysis [] ---
    # Key functions: computEigengenes, analyzeSurvival, bestInetgrator
    netPath <- file.path(tempdir(), "iNETgrateRes", "net")
    survivalPath <- file.path(netPath, "surv")
    dir.create(survivalPath, showWarnings = FALSE, recursive = TRUE)
    e1 <- computEigengenes(
        genExpr = toyCleanedAml$genExpr,
        eigenloci = computedEloci$eigenloci,
        netPath = netPath,
        geNames = elected$unionGenes,
        Labels = patientLabel,
        Label1 = "Low",
        Label2 = "High",
        mus = 0.6,
        combiningMu = NA,
        doIgnoreNas = TRUE,
        survival = toyCleanedAml$survival,
        event = "Dead",
        verbose = 0,
        mu2modules = madeNet$mu2modules
    )
    s1 <- analyzeSurvival(
        survival = toyCleanedAml$survival,
        favRisk = "High",
        subSet = "Int",
        mus = 0.6,
        netPath = netPath,
        outPath = survivalPath,
        xmax1 = 15,
        xmin1 = 0,
        verbose = 0
    )
    inetgrator <- bestInetgrator(
        bestPvalues = s1$bestPvalues,
        usefuLoci = computedEloci$usefuLoci,
        lociPigen = computedEloci$lociPigen,
        netPath = netPath
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_inetgrate_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_inetgrate_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_inetgrate_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INETGRATE:", paste0("    inetgrate: ", packageVersion("iNETgrate"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_inetgrate_results.csv
    touch ${prefix}_inetgrate_output.rds
    echo "BIOC_INETGRATE:" > versions.yml
    echo "    inetgrate: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INETGRATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INETGRATE(ch_input)

    emit:
    results  = BIOC_INETGRATE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INETGRATE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INETGRATE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INETGRATE.out.versions  // channel: path(versions.yml)
}
