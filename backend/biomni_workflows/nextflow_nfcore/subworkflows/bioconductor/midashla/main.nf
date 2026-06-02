#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: midasHLA
// MiDAS is a R package for immunogenetics data transformation and statistical analysis. MiDAS accepts 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/midasHLA/inst/doc/MiDAS_tutorial.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("midasHLA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MIDASHLA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-midashla"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-midashla:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-midashla:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_midashla_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_midashla_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_midashla_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(midasHLA)
    library(jsonlite)

    # --- load_all [] ---
    # Key functions: load_all
    knitr::opts_chunk$set(echo = TRUE, fig.align="center")
    devtools::load_all()
    # --- img [] ---
    # Key functions: img
    htmltools::img(
    src = knitr::image_uri("MiDAS_logo.png"),
    # --- read Hla Calls [] ---
    # Key functions: readHlaCalls
    read.table(
    file = system.file("extdata", "MiDAS_tut_pheno.txt", package = "midasHLA"),
    readHlaCalls(
    # --- show imported data [] ---
    # Key functions: kable_styling, scroll_box
    head(20) %>%
    kable(caption = "HLA data as imported by MiDAS") %>%
    kable_styling(bootstrap_options = c("striped", "hover", "condensed")) %>%
    # --- get frequencies [] ---
    # Key functions: getHlaFrequencies
    freq_HLA <- getHlaFrequencies(hla_calls = dat_HLA, compare = TRUE) %>%
    filter(Freq > 0.01)
    # --- show frequencies [] ---
    # Key functions: kable_styling
    head() %>%
    kable(caption = "HLA frequencies, compared to published references") %>%
    kable_styling(bootstrap_options = c("striped", "hover", "condensed"))
    # --- plot frequencies [] ---
    # Key functions: gather, ggplot, geom_bar, coord_flip, scale_y_continuous
    freq_HLA_long <- tidyr::gather(
    filter(grepl("^A", allele))
    ggplot2::ggplot(data = freq_HLA_long, ggplot2::aes(x = allele, y = freq, fill = population)) +
    # --- prep HLA [] ---
    # Key functions: prepareMiDAS
    HLA <- prepareMiDAS(
    # --- run HLA allelic [] ---
    # Key functions: glm, runMiDAS, kableResults
    HLA_model <- glm(disease ~ term, data = HLA, family = binomial())
    HLA_results <- runMiDAS(
    kableResults(HLA_results)
    # --- run HLA allelic cond [] ---
    # Key functions: runMiDAS, kableResults
    HLA_results_cond <- runMiDAS(
    kableResults(HLA_results_cond, scroll_box_height = "200px")
    # --- prepare HLA AA [] ---
    # Key functions: prepareMiDAS
    HLA_AA <- prepareMiDAS(
    # --- HLA AA to df [] ---
    # Key functions: assay
    assay() %>%
    t() %>%
    as.data.frame() %>%
    # --- show HLA AA [] ---
    # Key functions: kable_styling
    kable(dat_HLA_AA, caption = "HLA amino acid data as inferred by MiDAS") %>%
    kable_styling(bootstrap_options = c("striped", "hover", "condensed"))
    # --- run HLA AA omnibus [] ---
    # Key functions: glm, runMiDAS, kableResults
    HLA_AA_model <- glm(disease ~ term, data = HLA_AA, family = binomial())
    HLA_AA_omnibus_results <- runMiDAS(
    kableResults(HLA_AA_omnibus_results)
    # --- run HLA AA DQB1 9 [] ---
    # Key functions: runMiDAS, kableResults
    HLA_AA_DQB1_9_results <- runMiDAS(
    kableResults(HLA_AA_DQB1_9_results, scroll_box_height = "250px")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_midashla_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_midashla_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_midashla_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MIDASHLA:", paste0("    midashla: ", packageVersion("midasHLA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_midashla_results.csv
    touch ${prefix}_midashla_output.rds
    echo "BIOC_MIDASHLA:" > versions.yml
    echo "    midashla: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MIDASHLA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MIDASHLA(ch_input)

    emit:
    results  = BIOC_MIDASHLA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MIDASHLA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MIDASHLA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MIDASHLA.out.versions  // channel: path(versions.yml)
}
