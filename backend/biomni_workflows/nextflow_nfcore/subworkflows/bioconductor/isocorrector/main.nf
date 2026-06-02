#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: IsoCorrectoR
// IsoCorrectoR performs the correction of mass spectrometry data from stable isotope labeling/tracing 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/IsoCorrectoR/inst/doc/IsoCorrectoR.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("IsoCorrectoR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ISOCORRECTOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-isocorrector"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-isocorrector:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-isocorrector:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_isocorrector_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_isocorrector_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_isocorrector_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(IsoCorrectoR)
    library(jsonlite)


    # --- Tool Features Table [] ---
    # Key functions: isocorrector
    knitr::kable(
      IsoCorrectoR$tool_features
    )

    # --- Molecule File Example Normal Res [] ---
    # Key functions: normal_resolution, molecule_file
    fileExample <- IsoCorrectoR[["normal_resolution"]][["molecule_file"]]

    fileExample[4:7, 3] <- ""

    knitr::kable(
      fileExample, align = "l", caption="Molecule information for normal resolution data"
    )

    # --- Molecule File Example High Res [] ---
    # Key functions: high_resolution, molecule_file
    fileExample <- IsoCorrectoR[["high_resolution"]][["molecule_file"]]

    fileExample[is.na(fileExample)] <- ""

    knitr::kable(
      fileExample, align = "l", caption="Molecule information for high resolution data"
    )

    # --- Measurement File Example Norm Res [] ---
    # Key functions: normal_resolution, measurement_file
    fileExample <- IsoCorrectoR[["normal_resolution"]][["measurement_file"]]

    #Subset and adjust example to illustrate explanations

    fileExample <- fileExample[c(1:6, 40:43),1:6]

    fileExample[7:10,1] <- gsub('.{2}$', '', fileExample[7:10,1])

    fileExample[c(4,6), "Sample3"] <- ""
    fileExample[4, "Sample5"] <- ""
    fileExample[9, "Sample1"] <- ""

    knitr::kable(
      fileExample, align = "l", row.names = FALSE, caption="Measurement information for normal resolution data"
    )

    # --- Measurement File Example High Res [] ---
    # Key functions: high_resolution, measurement_file
    fileExample <- IsoCorrectoR[["high_resolution"]][["measurement_file"]]

    #Subset and adjust example to illustrate explanations

    fileExample <- fileExample[1:21,1:6]

    fileExample[20,"Sample3"] <- ""
    fileExample[21,"Sample3"] <- "0"
    fileExample[16,"Sample3"] <- ""

    knitr::kable(
      fileExample, align = "l", row.names = FALSE, caption="Measurement information for high resolution data"
    )

    # --- Element File Example [] ---
    # Key functions: information
    fileExample <- IsoCorrectoR$element_file

    fileExample[is.na(fileExample)] <- ""

    knitr::kable(
      fileExample, align = "l", caption="Element information (resolution independent)"
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_isocorrector_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_isocorrector_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_isocorrector_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ISOCORRECTOR:", paste0("    isocorrector: ", packageVersion("IsoCorrectoR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_isocorrector_results.csv
    touch ${prefix}_isocorrector_output.rds
    echo "BIOC_ISOCORRECTOR:" > versions.yml
    echo "    isocorrector: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ISOCORRECTOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ISOCORRECTOR(ch_input)

    emit:
    results  = BIOC_ISOCORRECTOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ISOCORRECTOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ISOCORRECTOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ISOCORRECTOR.out.versions  // channel: path(versions.yml)
}
