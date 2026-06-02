#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: koinar
// A client to simplify fetching predictions from the Koina web service. Koina is a model repository en
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/koinar/inst/doc/koina.R
// Upstream  : Spectra, httptest, msdata
// Downstream: none
//
// Install: BiocManager::install("koinar")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KOINAR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-koinar"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-koinar:1.0.2--r44_0' :
        'quay.io/biocontainers/bioconductor-koinar:1.0.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_koinar_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_koinar_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_koinar_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Koina)
    library(SpectrumSimilarity)
    library(jsonlite)

    # --- Koina [] ---
    # Key functions: Koina
    prosit2019 <- koinar::Koina(
    # --- predict With Koina Model [] ---
    # Key functions: predictWithKoinaModel
    input <- data.frame(
    peptide_sequences = c("LGGNEQVTR", "GAGSSEPVTGLDAK"),
    collision_energies = c(25, 25),
    # --- Koina [] ---
    # Key functions: Koina
    pred_prosit <- prosit2019$predict((input))
    ms2pip <- koinar::Koina(
    pred_ms2pip <- ms2pip$predict(input)
    # --- xyplot [] ---
    # Key functions: xyplot
    lattice::xyplot(intensities ~ mz | model * peptide_sequences,
    group = grepl("y", annotation),
    data = rbind(
    # --- Spectrum Similarity [] ---
    # Key functions: SpectrumSimilarity
    sim <- OrgMassSpecR::SpectrumSimilarity(pred_prosit[pred_prosit$peptide_sequences == peptide_sequence, c("mz", "intensities")],
    pred_ms2pip[pred_ms2pip$peptide_sequences == peptide_sequence, c("mz", "intensities")],
    title(main = paste(peptide_sequence, "| Spectrum similarity", round(sim, 3)))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_koinar_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_koinar_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_koinar_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_KOINAR:", paste0("    koinar: ", packageVersion("koinar"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_koinar_results.csv
    touch ${prefix}_koinar_output.rds
    echo "BIOC_KOINAR:" > versions.yml
    echo "    koinar: 0.0.0" >> versions.yml
    """
}


workflow BIOC_KOINAR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_KOINAR(ch_input)

    emit:
    results  = BIOC_KOINAR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_KOINAR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_KOINAR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_KOINAR.out.versions  // channel: path(versions.yml)
}
