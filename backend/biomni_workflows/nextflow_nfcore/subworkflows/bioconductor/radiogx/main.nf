#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: RadioGx
// Computational tool box for radio-genomic analysis which integrates radio-response data, radio-biolog
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/RadioGx/inst/doc/RadioGx.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("RadioGx")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RADIOGX {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-radiogx"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-radiogx:2.10.0--r44_0' :
        'quay.io/biocontainers/bioconductor-radiogx:2.10.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_radiogx_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_radiogx_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_radiogx_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(RadioGx)
    library(jsonlite)

    # --- Dataset Exploration and Metadata Extraction [radiationInfo, radiationTypes, mDataNames, phenoInfo, availableRSets] ---
    # Key functions: availableRSets, radiationInfo, radiationTypes, mDataNames, phenoInfo
    data(clevelandSmall)
    rsets <- availableRSets()
    rad_info <- radiationInfo(clevelandSmall)
    rad_types <- radiationTypes(clevelandSmall)
    mol_names <- mDataNames(clevelandSmall)
    pheno_info <- phenoInfo(clevelandSmall, "cnv")

    # --- Molecular and Response Data Access [molecularProfiles, treatmentResponse, sensitivityRaw, sensitivityProfiles, sensitivityInfo] ---
    # Key functions: molecularProfiles, treatmentResponse, sensitivityRaw, sensitivityProfiles, sensitivityInfo
    data(clevelandSmall)
    m_prof <- molecularProfiles(clevelandSmall, "rnaseq")
    sens_resp <- treatmentResponse(clevelandSmall)
    sens_raw <- sensitivityRaw(clevelandSmall)
    sens_prof <- sensitivityProfiles(clevelandSmall)
    sens_info <- sensitivityInfo(clevelandSmall)

    # --- Dose-Response Curve Fitting and Metric Calculation [linearQuadraticModel, computeSF2, computeD10, computeAUC] ---
    # Key functions: linearQuadraticModel, computeSF2, computeD10, computeAUC
    data(clevelandSmall)
    sens_raw <- sensitivityRaw(clevelandSmall)
    rad_doses <- sens_raw[1, , "Dose"]
    surv_fracs <- sens_raw[1, , "Viability"]
    lq_model <- linearQuadraticModel(D = rad_doses, SF = surv_fracs)
    sf2 <- computeSF2(pars = lq_model)
    d10 <- computeD10(pars = lq_model)
    auc <- computeAUC(
        D = rad_doses,
        pars = lq_model,
        lower = 0,
        upper = 1
    )

    # --- Dose-Response Visualization [doseResponseCurve, cellInfo] ---
    # Key functions: doseResponseCurve, cellInfo
    data(clevelandSmall)
    cell_id <- cellInfo(clevelandSmall)$sampleid[5]
    doseResponseCurve(
        rSets = list(clevelandSmall),
        cellline = cell_id
    )
    doseResponseCurve(
        Ds = list("Exp1" = c(0, 2, 4, 6)),
        SFs = list("Exp1" = c(1, 0.6, 0.4, 0.2)),
        plot.type = "Both"
    )

    # --- Profile Summarization and Signature Computation [summarizeSensitivityProfiles, summarizeMolecularProfiles, radSensitivitySig, fNames] ---
    # Key functions: summarizeSensitivityProfiles, summarizeMolecularProfiles, radSensitivitySig, fNames
    data(clevelandSmall)
    sens_sum <- summarizeSensitivityProfiles(clevelandSmall)
    mol_sum <- summarizeMolecularProfiles(
        clevelandSmall,
        mDataType = "rna",
        summary.stat = "median",
        fill.missing = FALSE
    )
    feats <- fNames(clevelandSmall, "rna")[2:5]
    rad_sig <- radSensitivitySig(
        clevelandSmall,
        mDataType = "rna",
        features = feats,
        nthread = 1
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_radiogx_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_radiogx_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_radiogx_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RADIOGX:", paste0("    radiogx: ", packageVersion("RadioGx"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_radiogx_results.csv
    touch ${prefix}_radiogx_output.rds
    echo "BIOC_RADIOGX:" > versions.yml
    echo "    radiogx: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RADIOGX_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RADIOGX(ch_input)

    emit:
    results  = BIOC_RADIOGX.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RADIOGX.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RADIOGX.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RADIOGX.out.versions  // channel: path(versions.yml)
}
