#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: genomicInstability
// This package contain functions to run genomic instability analysis (GIA) from scRNA-Seq data. GIA es
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/genomicInstability/inst/doc/genomicInstability.R
// Upstream  : ExperimentHub, SingleCellExperiment, pROC
// Downstream: none
//
// Install: BiocManager::install("genomicInstability")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENOMICINSTABILITY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genomicinstability"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genomicinstability:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genomicinstability:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genomicinstability_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genomicinstability_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genomicinstability_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(jsonlite)

    # --- Experimenthub [] ---
    # Key functions: ExperimentHub
    library(SingleCellExperiment)
    library(ExperimentHub)
    eh <- ExperimentHub()
    dset <- eh[["EH5419"]]
    # --- Assays [] ---
    # Key functions: assays, sample, colData
    tpm_matrix <- assays(dset)$TPM
    set.seed(1)
    pos <- sample(ncol(tpm_matrix), 500)
    tpm_matrix <- tpm_matrix[, pos]
    metadata <- colData(dset)
    # --- Infercnv [] ---
    # Key functions: inferCNV
    cnv <- inferCNV(tpm_matrix)
    class(cnv)
    names(cnv)
    dim(cnv$nes)
    # --- Genomicinstabilityscore [] ---
    # Key functions: genomicInstabilityScore
    cnv <- genomicInstabilityScore(cnv)
    names(cnv)
    length(cnv$gis)
    # --- Density [] ---
    # Key functions: density
    par(mai=c(.8, .8, .2, .2))
    plot(density(cnv$gis), lwd=2, xlab="GIS", main="")
    # --- Gilikelihood [] ---
    # Key functions: giLikelihood
    cnv <- giLikelihood(cnv)
    # --- Likelihood [] ---
    # Key functions: giDensityPlot
    # Plotting the density distribution for GIS and fitted models
    par(mai=c(.8, .8, .2, .8))
    giDensityPlot(cnv, ylim=c(0, .8))
    # Adding the likelihood data and second-axis
    pos <- order(cnv$gis)
    # --- Infercnv [] ---
    # Key functions: inferCNV
    cnv_norm <- inferCNV(tpm_matrix, nullmat=tpm_matrix[, cnv$gi_likelihood<.25,
                                                        drop=FALSE])
    names(cnv_norm)
    # --- Genomicinstabilityscore [] ---
    # Key functions: genomicInstabilityScore
    cnv_norm <- genomicInstabilityScore(cnv_norm, likelihood=TRUE)
    # --- Fitnull [] ---
    # Key functions: giDensityPlot
    # Plotting the density distribution for GIS and fitted models
    par(mai=c(.8, .8, .2, .8))
    giDensityPlot(cnv_norm, ylim=c(0, 1.1))
    # Adding the likelihood data and second-axis
    pos <- order(cnv_norm$gis)
    # --- Test [] ---
    # Key functions: test
    fisher.test(metadata_tumor, cnv_norm$gi_likelihood>.5, alternative="greater")
    # --- Roc [] ---
    # Key functions: roc
    # Loading the pROC package
    library(pROC)
    roc_res <- roc(response=as.numeric(metadata_tumor), predictor=cnv_norm$gi_likelihood, auc=TRUE, ci=TRUE)
    par(mai=c(.8, .8, .2, .8))
    plot(roc_res)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genomicinstability_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genomicinstability_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genomicinstability_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENOMICINSTABILITY:", paste0("    genomicinstability: ", packageVersion("genomicInstability"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genomicinstability_results.csv
    touch ${prefix}_genomicinstability_output.rds
    echo "BIOC_GENOMICINSTABILITY:" > versions.yml
    echo "    genomicinstability: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENOMICINSTABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENOMICINSTABILITY(ch_input)

    emit:
    results  = BIOC_GENOMICINSTABILITY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENOMICINSTABILITY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENOMICINSTABILITY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENOMICINSTABILITY.out.versions  // channel: path(versions.yml)
}
