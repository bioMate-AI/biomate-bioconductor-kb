#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: NormqPCR
// Functions for the selection of optimal reference genes and the normalisation of real-time quantitati
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/NormqPCR/inst/doc/NormqPCR.R
// Upstream  : RColorBrewer, ReadqPCR
// Downstream: none
//
// Install: BiocManager::install("NormqPCR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NORMQPCR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-normqpcr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-normqpcr:1.52.0--r44_0' :
        'quay.io/biocontainers/bioconductor-normqpcr:1.52.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_normqpcr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_normqpcr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_normqpcr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ComputeNRQs)
    library(jsonlite)

    # --- path [] ---
    # Key functions: path, qPCR, exprs
    library(ReadqPCR) # load the ReadqPCR library
    library(NormqPCR)
    path <- system.file("exData", package = "NormqPCR")
    qPCR.example.techReps <- file.path(path, "qPCR.techReps.txt")
    qPCRBatch.qPCR.techReps <- read.qPCR(qPCR.example.techReps)
    # --- Combine Read.Qpcr.Tech.Reps [] ---
    # Key functions: combineTechReps
    combinedTechReps <- combineTechReps(qPCRBatch.qPCR.techReps)
    combinedTechReps
    # --- Taqman Read [] ---
    # Key functions: path, taqman
    path <- system.file("exData", package = "NormqPCR")
    taqman.example <- file.path(path, "/example.txt")
    qPCRBatch.taqman <- read.taqman(taqman.example)
    # --- Taqman Detector Example [] ---
    # Key functions: exprs
    exprs(qPCRBatch.taqman)["Ccl20.Rn00570287_m1",]
    # --- Replace Above Cutoff [] ---
    # Key functions: replaceAboveCutOff, exprs
    qPCRBatch.taqman.replaced <- replaceAboveCutOff(qPCRBatch.taqman,
                                                    newVal = NA, cutOff = 35)
    exprs(qPCRBatch.taqman.replaced)["Ccl20.Rn00570287_m1",]
    # --- Replace Nas With 40 [] ---
    # Key functions: replaceNAs, exprs
    qPCRBatch.taqman.replaced <- replaceNAs(qPCRBatch.taqman, newNA = 40)
    exprs(qPCRBatch.taqman.replaced)["Ccl20.Rn00570287_m1",]
    # --- Construct Contrast Matrix [] ---
    # Key functions: sampleNames
    sampleNames(qPCRBatch.taqman)
    a <- c(0,0,1,1,0,0,1,1) # one for each sample type, with 1 representing
    b <- c(1,1,0,0,1,1,0,0) # position of sample type in samplenames vector
    contM <- cbind(a,b)
    colnames(contM) <- c("case","control") # set the names of each sample type
    # --- Replace 3 Or More Nas With All Nas [] ---
    # Key functions: makeAllNewVal
    qPCRBatch.taqman.replaced <- makeAllNewVal(qPCRBatch.taqman, contM,
                                               sMaxM, newVal=NA)
    # --- Ccl20 Is Now All Nas [] ---
    # Key functions: exprs
    exprs(qPCRBatch.taqman.replaced)["Ccl20.Rn00570287_m1",]
    # --- Normqpcr [] ---
    # Key functions: exprs
    options(width = 68)
    data(geNorm)
    str(exprs(geNorm.qPCRBatch))
    # --- Genorm [] ---
    # Key functions: factor, selectHKs, featureNames
    tissue <- as.factor(c(rep("BM", 9),  rep("FIB", 20), rep("LEU", 13),
                        rep("NB", 34), rep("POOL", 9)))
    res.BM <- selectHKs(geNorm.qPCRBatch[,tissue == "BM"], method = "geNorm",
                        Symbols = featureNames(geNorm.qPCRBatch),
                        minNrHK = 2, log = FALSE)
    # --- Table3 [] ---
    # Key functions: frame
    ranks <- data.frame(c(1, 1:9), res.BM$ranking, res.POOL$ranking,
                        res.FIB$ranking, res.LEU$ranking,
                        res.NB$ranking)
    names(ranks) <- c("rank", "BM", "POOL", "FIB", "LEU", "NB")
    ranks
    # --- Fig2 [] ---
    # Key functions: pal, matplot
    library(RColorBrewer)
    mypalette <- brewer.pal(5, "Set1")
    matplot(cbind(res.BM$meanM, res.POOL$meanM, res.FIB$meanM,
                  res.LEU$meanM, res.NB$meanM), type = "b",
            ylab = "Average expression stability M",
    # --- pal [] ---
    # Key functions: pal, 3
    mypalette <- brewer.pal(8, "YlGnBu")
    barplot(cbind(res.POOL$variation, res.LEU$variation, res.NB$variation,
                  res.FIB$variation, res.BM$variation), beside = TRUE,
            col = mypalette, space = c(0, 2),
            names.arg = c("POOL", "LEU", "NB", "FIB", "BM"),
    # --- Normfinder [] ---
    # Key functions: pData, stabMeasureRho, al
    data(Colon)
    Colon
    Class <- pData(Colon)[,"Classification"]
    res.Colon <- stabMeasureRho(Colon, group = Class, log = FALSE)
    sort(res.Colon) # see Table 3 in Andersen et al (2004)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_normqpcr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_normqpcr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_normqpcr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NORMQPCR:", paste0("    normqpcr: ", packageVersion("NormqPCR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_normqpcr_results.csv
    touch ${prefix}_normqpcr_output.rds
    echo "BIOC_NORMQPCR:" > versions.yml
    echo "    normqpcr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NORMQPCR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_NORMQPCR(ch_input)

    emit:
    results  = BIOC_NORMQPCR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NORMQPCR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NORMQPCR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NORMQPCR.out.versions  // channel: path(versions.yml)
}
