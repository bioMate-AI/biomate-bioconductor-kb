#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: aCGH
// Functions for reading aCGH data from image analysis output files and clone information files, creati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/aCGH/inst/doc/aCGH.R
// Upstream  : none
// Downstream: CRImage
//
// Install: BiocManager::install("aCGH")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ACGH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-acgh"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-acgh:1.84.0--r44_0' :
        'quay.io/biocontainers/bioconductor-acgh:1.84.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_acgh_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_acgh_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_acgh_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Samples)
    library(Surv)
    library(jsonlite)

    # --- Process [] ---
    # Key functions: process
    ex.acgh <-
        aCGH.process(ex.acgh, chrom.remove.threshold = 23, prop.missing = .25, sample.quality.threshold = .4, unmapScreen=TRUE, dupRemove = FALSE)
    # --- Imputed [] ---
    # Key functions: imputed, lowess
    log2.ratios.imputed(ex.acgh) <- impute.lowess(ex.acgh, maxChrom=24)
    # --- Data [] ---
    # Key functions: data
    data(colorectal)
    colorectal
    summary(colorectal)
    # --- Plotgenome [] ---
    # Key functions: plotGenome
    plotGenome(ex.acgh, samples=2, Y = FALSE)
    # --- Hmm [] ---
    # Key functions: hmm, states, merged, mergeHmmStates, samples, Samples, events, postscript
    ## Determining hmm states of the clones. In the interest of time,
    ##we have commented this step out and used pre-computed results.
    ##hmm(ex.acgh) <- find.hmm.states(ex.acgh)
    hmm(ex.acgh) <- ex.acgh.hmm
    ## Merging hmm states
    # --- Plothmmstates [] ---
    # Key functions: plotHmmStates
    plotHmmStates(colorectal, sample.ind = 1, chr = 1)
    # --- Plotfreqstat [] ---
    # Key functions: plotFreqStat
    plotFreqStat(colorectal, all = T)
    # --- Clones [] ---
    # Key functions: clones
    summarize.clones(colorectal)[1:10 ,]
    # --- Func [] ---
    # Key functions: func, ratios, samples
    factor <- 3
    tbl <- threshold.func(log2.ratios(colorectal),
                posThres=factor*(sd.samples(colorectal)$madGenome))
    rownames(tbl) <- clone.names(colorectal)
    colnames(tbl) <- sample.names(colorectal)
    # --- Func [] ---
    # Key functions: func
    col.fga <- fga.func(colorectal, factor=3,chrominfo=human.chrom.info.Jul03)
    cbind(gainP=col.fga$gainP,lossP=col.fga$lossP)[1:5,]
    # --- Colnames [] ---
    # Key functions: phenotype, na, info, imputed, maxT
    colnames(phenotype(colorectal))
    sex <- phenotype(colorectal)$sex
    sex.na <- !is.na(sex)
    index.clones.use <- which(clones.info(colorectal)$Chrom < 23)
    colorectal.na <- colorectal[ index.clones.use,sex.na , keep=TRUE]
    # --- Plotfreqstat [] ---
    # Key functions: plotFreqStat
    plotFreqStat(colorectal.na, resT.sex, sex[sex.na], factor=3, titles =
                 c("Female", "Male"), X = FALSE, Y = FALSE)
    # --- Plotsummaryprofile [] ---
    # Key functions: plotSummaryProfile
    plotSummaryProfile(colorectal, response = sex,
                       titles = c("Female", "Male"),
                       X = FALSE, Y = FALSE, maxChrom = 22)
    # --- Gainloss [] ---
    # Key functions: gainLoss, ratios, samples, info, imputed, maxT
    factor <- 3
    minChanged <- 0.1
    gainloss <- gainLoss(log2.ratios(colorectal)[,sex.na], cols=1:length(which(sex.na)), thres=(factor*(sd.samples(colorectal)$madGenome))[sex.na])
    ind.clones.use <- which(gainloss$gainP >= minChanged | gainloss$lossP>= minChanged & clones.info(colorectal)$Chrom < 23)
    colorectal.na <- colorectal[ind.clones.use,sex.na, keep=TRUE]
    # --- Plotfreqstat [] ---
    # Key functions: plotFreqStat
    plotFreqStat(colorectal.na, resT.sex, sex[sex.na],factor=factor,titles = c("Male", "Female"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_acgh_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_acgh_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_acgh_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ACGH:", paste0("    acgh: ", packageVersion("aCGH"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_acgh_results.csv
    touch ${prefix}_acgh_output.rds
    echo "BIOC_ACGH:" > versions.yml
    echo "    acgh: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ACGH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ACGH(ch_input)

    emit:
    results  = BIOC_ACGH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ACGH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ACGH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ACGH.out.versions  // channel: path(versions.yml)
}
