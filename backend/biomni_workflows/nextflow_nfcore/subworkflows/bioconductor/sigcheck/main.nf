#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SigCheck
// While gene signatures are frequently used to predict phenotypes (e.g. predict prognosis of cancer pa
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SigCheck/inst/doc/SigCheck.R
// Upstream  : BiocParallel, breastCancerNKI
// Downstream: none
//
// Install: BiocManager::install("SigCheck")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SIGCHECK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-sigcheck"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-sigcheck:2.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-sigcheck:2.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_sigcheck_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_sigcheck_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_sigcheck_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MulticoreParam)
    library(jsonlite)

    # --- Loaddata [] ---
    # Key functions: data
    library(breastCancerNKI)
    data(nki)
    nki
    # --- Excludena [] ---
    # Key functions: na
    dim(nki)
    nki <- nki[,!is.na(nki$e.dmfs)]
    dim(nki)
    # --- Loadknown [] ---
    # Key functions: data
    library(SigCheck)
    data(knownSignatures)
    names(knownSignatures)
    # --- Sigchecksurvival [] ---
    # Key functions: sigCheck
    check <- sigCheck(nki, classes="e.dmfs", survival="t.dmfs",
                      signature=knownSignatures$cancer$VANTVEER,
                      annotation="HUGO.gene.symbol",
                      validationSamples=which(nki$series=="NKI2"))
    check
    # --- Sigcheckallsurvivalnoeval [] ---
    # Key functions: sigCheckAll
    ## nkiResults <- sigCheckAll(check, iterations=1000)
    # --- Sigcheckplotsurvival [] ---
    # Key functions: sigCheckPlot
    sigCheckPlot(nkiResults)
    # --- Sigcheckhi [] ---
    # Key functions: sigCheck
    par(mfrow=c(2,2))
    p5 <- sigCheck(check,
                  scoreMethod="High",threshold=.5,
                  plotTrainingKM=F)@survivalPval
    p66 <- sigCheck(check,
    # --- Sigchecksurvivalclass [] ---
    # Key functions: sigCheck
    check <- sigCheck(check, scoreMethod="classifier")
    check@survivalPval
    # --- Sigcheckclassifier [] ---
    # Key functions: sigCheck
    check <- sigCheck(nki, classes="e.dmfs",
                      signature=knownSignatures$cancer$VANTVEER,
                      annotation="HUGO.gene.symbol",
                      validationSamples=which(nki$series=="NKI2"),
                      scoreMethod="classifier")
    # --- Sigcheckclassify [] ---
    # Key functions: sigCheckRandom, sigCheckKnown
    ## classifyRandom <- sigCheckRandom(check, iterations=1000)
    ## classifyKnown <- sigCheckKnown(check)
    # --- Loadclassifyresults [] ---
    # Key functions: data
    data(classifyResults)
    # --- Sigclassifyplot [] ---
    # Key functions: sigCheckPlot
    par(mfrow=c(1,2))
    sigCheckPlot(classifyRandom, classifier=TRUE)
    sigCheckPlot(classifyKnown,  classifier=TRUE)
    # --- Msigdbnoeval [] ---
    # Key functions: gmt, sigCheckKnown, sigCheckPlot
    ## c6.oncogenic <- read.gmt('c6.all.v5.0.symbols.gmt')
    ## check.c6 <- sigCheckKnown(check, c6.oncogenic)
    ## sigCheckPlot(check.c6)
    # --- Multicoreparam [] ---
    # Key functions: MulticoreParam, register
    CoresToUse <- 6
    library(BiocParallel)
    mcp <- MulticoreParam(workers=CoresToUse)
    register(mcp, default=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_sigcheck_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_sigcheck_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_sigcheck_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SIGCHECK:", paste0("    sigcheck: ", packageVersion("SigCheck"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_sigcheck_results.csv
    touch ${prefix}_sigcheck_output.rds
    echo "BIOC_SIGCHECK:" > versions.yml
    echo "    sigcheck: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SIGCHECK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SIGCHECK(ch_input)

    emit:
    results  = BIOC_SIGCHECK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SIGCHECK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SIGCHECK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SIGCHECK.out.versions  // channel: path(versions.yml)
}
