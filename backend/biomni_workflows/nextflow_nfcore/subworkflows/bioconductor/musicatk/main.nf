#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: musicatk
// Mutational signatures are carcinogenic exposures or aberrant cellular processes that can cause alter
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/musicatk/inst/doc/musicatk.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("musicatk")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSICATK {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-musicatk"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-musicatk:2.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-musicatk:2.0.0--r44_0'}"

    input:
    tuple val(meta), path(vcf_object)

    output:
    tuple val(meta), path("${meta.id}_musicatk_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_musicatk_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_musicatk_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(musicatk)
    library(jsonlite)

    # --- Count Table Construction [] ---
    # Key functions: build_standard_table, annotate_transcript_strand, build_custom_table
    build_standard_table(musica, g = g, table_name = "SBS96")
    annotate_transcript_strand(musica, "19", build_table = FALSE)
    build_custom_table(
        musica = musica, variant_annotation = "Transcript_Strand",
        name = "Transcript_Strand",
        description = "A table of transcript strand of variants",
        data_factor = c("T", "U"), overwrite = TRUE
    )


    # --- Signature Discovery and Evaluation [] ---
    # Key functions: compare_k_vals, discover_signatures, exposures, signatures
    k_comparison <- compare_k_vals(musica, "SBS96",
        reps = 5, min_k = 2, max_k = 4, algorithm = "nmf"
    )
    discover_signatures(
        musica = musica, modality = "SBS96", num_signatures = 3,
        algorithm = "nmf", model_id = "ex_result", nstart = 10
    )
    expos <- exposures(musica, "result", "SBS96", "ex_result")
    sigs <- signatures(musica, "result", "SBS96", "ex_result")


    # --- Signature Prediction and Comparison [] ---
    # Key functions: predict_exposure, get_model, compare_results
    data("cosmic_v2_sigs")
    predict_exposure(
        musica = musica, modality = "SBS96",
        signature_res = cosmic_v2_sigs, model_id = "ex_pred_result",
        signatures_to_use = c(1, 4, 7, 13), algorithm = "lda"
    )
    model <- get_model(musica, "result", "SBS96", "ex_result")
    predict_exposure(
        musica = musica, modality = "SBS96",
        signature_res = model, algorithm = "lda",
        model_id = "pred_our_sigs"
    )
    compare_results(musica, "ex_pred_result", "pred_our_sigs", 0.60)


    # --- Visualization and Dimensionality Reduction [] ---
    # Key functions: plot_signatures, plot_exposures, create_umap, plot_umap
    plot_signatures(musica, model_id = "ex_result", modality = "SBS96")
    plot_exposures(musica, "ex_result", plot_type = "bar")
    create_umap(musica, "ex_result")
    plot_umap(musica, "ex_result")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_musicatk_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_musicatk_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_musicatk_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MUSICATK:", paste0("    musicatk: ", packageVersion("musicatk"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_musicatk_results.csv
    touch ${prefix}_musicatk_output.rds
    echo "BIOC_MUSICATK:" > versions.yml
    echo "    musicatk: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MUSICATK_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(vcf_object) ]

    main:
    BIOC_MUSICATK(ch_input)

    emit:
    results  = BIOC_MUSICATK.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MUSICATK.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MUSICATK.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MUSICATK.out.versions  // channel: path(versions.yml)
}
