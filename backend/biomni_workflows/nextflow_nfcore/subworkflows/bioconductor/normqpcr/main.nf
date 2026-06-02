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
    library(NormqPCR)
    library(ComputeNRQs)
    library(jsonlite)

    # --- Stability Analysis with NormFinder [] ---
    # Key functions: stabMeasureRho, selectHKs, featureNames
    data(Colon)
    Class <- pData(Colon)[, "Classification"]
    res.Colon <- stabMeasureRho(Colon, group = Class, log = FALSE)
    sorted.Colon <- sort(res.Colon)
    hk.NormFinder <- selectHKs(Colon, group = Class, log = FALSE,
                               trace = FALSE,
                               Symbols = featureNames(Colon),
                               minNrHKs = 12,
                               method = "NormFinder")


    # --- Delta Cq Normalisation [] ---
    # Key functions: deltaCq, exprs, featureNames
    data(geNorm)
    hkg <- featureNames(geNorm.qPCRBatch)[1]
    qPCRBatch.norm <- deltaCq(qPCRBatch = geNorm.qPCRBatch,
                              hkgs = hkg,
                              calc = "arith")
    norm.exprs <- exprs(qPCRBatch.norm)


    # --- Delta Delta Cq Analysis [] ---
    # Key functions: deltaDeltaCq, sampleNames, featureNames
    data(geNorm)
    hkg <- featureNames(geNorm.qPCRBatch)[1]
    samples <- sampleNames(geNorm.qPCRBatch)
    contM <- cbind(rep(c(1, 0), length.out = length(samples)),
                   rep(c(0, 1), length.out = length(samples)))
    colnames(contM) <- c("interestingPhenotype", "wildTypePhenotype")
    rownames(contM) <- samples
    ddCq.res <- deltaDeltaCq(qPCRBatch = geNorm.qPCRBatch,
                             maxNACase = 5, maxNAControl = 5,
                             hkg = hkg, contrastM = contM,
                             case = "interestingPhenotype",
                             control = "wildTypePhenotype",
                             statCalc = "geom", hkgCalc = "arith")


    # --- Relative Quantification with Efficiencies [] ---
    # Key functions: combineTechRepsWithSD, ComputeNRQs, effs<-, se.effs<-
    data(geNorm)
    Cq.data1 <- combineTechRepsWithSD(geNorm.qPCRBatch)
    effs.matrix <- matrix(1.9, nrow = nrow(Cq.data1), ncol = 1)
    se.effs.matrix <- matrix(0.05, nrow = nrow(Cq.data1), ncol = 1)
    rownames(effs.matrix) <- featureNames(Cq.data1)
    rownames(se.effs.matrix) <- featureNames(Cq.data1)
    effs(Cq.data1) <- effs.matrix
    se.effs(Cq.data1) <- se.effs.matrix
    res <- ComputeNRQs(Cq.data1, hkgs = featureNames(Cq.data1)[1:2])
    nrqs <- exprs(res)

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
