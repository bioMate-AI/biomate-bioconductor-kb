#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Xeva
// The Xeva package provides efficient and powerful functions for patient-drived xenograft (PDX) based 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Xeva/inst/doc/Xeva.R
// Upstream  : Biobase
// Downstream: none
//
// Install: BiocManager::install("Xeva")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_XEVA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-xeva"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-xeva:1.22.1--r44_0' :
        'quay.io/biocontainers/bioconductor-xeva:1.22.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_xeva_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_xeva_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_xeva_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Xeva)
    library(jsonlite)


    # --- L2 [] ---
    # Key functions: modelInfo, getExperiment, batchInfo
    data(brca)
    print(brca)
    brca.mod <- modelInfo(brca)
    dim(brca.mod)
    brca.mod[1:4, ]
    model.data <- getExperiment(brca, model.id = "X.1004.BG98")
    head(model.data)
    batch.name <- batchInfo(brca)
    batch.name[1:4]

    # --- Batch2 [] ---
    # Key functions: batchInfo, plotPDX, paclitaxel, untreated
    batchInfo(brca, batch = "X-1004.binimetinib")
    plotPDX(brca, batch = "X-4567.BKM120")
    plotPDX(brca, batch = "X-4567.BKM120", vol.normal = TRUE, control.col = "#a6611a",
            treatment.col = "#018571", major.line.size = 1, max.time = 40)
    plotPDX(brca, patient.id="X-3078", drug="paclitaxel",control.name = "untreated")

    # --- Repplot1 [] ---
    # Key functions: plotPDX, repdx, errorbar, ribbon, summarizeResponse, mRECIST
    data("repdx")
    plotPDX(repdx, vol.normal = TRUE, batch = "P1")
    plotPDX(repdx, batch = "P3", SE.plot = "errorbar")
    plotPDX(repdx, batch = "P4", vol.normal = TRUE,  SE.plot = "ribbon")
    brca.mr <- summarizeResponse(brca, response.measure = "mRECIST")
    brca.mr[1:5, 1:4]

    # --- Water Fall1 [] ---
    # Key functions: waterfall, binimetinib, best.average.response, summarizeMolecularProfiles, exprs, mutation, response, repdx
    waterfall(brca, drug="binimetinib", res.measure="best.average.response")
    mut <- summarizeMolecularProfiles(brca,drug = "BYL719", mDataType="mutation")
    model.type <- Biobase::exprs(mut)["CDK13", ]
    model.type[grepl("Mut", model.type)] <- "mutation"
    model.type[model.type!="mutation"] <- "wild type"
    model.color <- list("mutation"="#b2182b", "wild type"="#878787")
    waterfall(brca, drug="BYL719", res.measure="best.average.response",
              model.id=names(model.type), model.type= model.type,
              type.color = model.color)
    data("repdx")
    response(repdx, batch="P1", res.measure="angle")
    data("repdx")
    response(repdx, batch="P1", res.measure="lmm")

    # --- Biomarker1 [] ---
    # Key functions: drugSensitivitySig, tamoxifen, slope, best.average.response, pearson, extdata, model.csv
    data(brca)
    drugSensitivitySig(object=brca, drug="tamoxifen", mDataType="RNASeq",
                       features=c(1,2,3,4,5), sensitivity.measure="slope", fit="lm")
    data(brca)
    drugSensitivitySig(object=brca, drug="tamoxifen", mDataType="RNASeq",
                       features=c(1,2,3,4,5),
                       sensitivity.measure="best.average.response", fit = "lm")
    data(brca)
    drugSensitivitySig(object=brca, drug="tamoxifen", mDataType="RNASeq",
                       features=c(1,2,3,4,5),
                       sensitivity.measure="best.average.response", fit="pearson")
    model=read.csv(system.file("extdata", "model.csv", package = "Xeva"))
    head(model)

    # --- X2 [] ---
    # Key functions: extdata, drug.csv, experiments.csv, readRDS, batch_list.rds, rnaseq.rds
    drug=read.csv(system.file("extdata", "drug.csv", package = "Xeva"))
    head(drug)
    experiment=read.csv(system.file("extdata","experiments.csv",package="Xeva"))
    head(experiment)
    expDesign=readRDS(system.file("extdata","batch_list.rds",package="Xeva"))
    expDesign[[1]]
    RNASeq=readRDS(system.file("extdata", "rnaseq.rds", package = "Xeva"))
    print(RNASeq)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_xeva_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_xeva_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_xeva_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_XEVA:", paste0("    xeva: ", packageVersion("Xeva"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_xeva_results.csv
    touch ${prefix}_xeva_output.rds
    echo "BIOC_XEVA:" > versions.yml
    echo "    xeva: 0.0.0" >> versions.yml
    """
}


workflow BIOC_XEVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_XEVA(ch_input)

    emit:
    results  = BIOC_XEVA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_XEVA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_XEVA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_XEVA.out.versions  // channel: path(versions.yml)
}
