#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: plyinteractions
// Operate on `GInteractions` objects as tabular data using `dplyr`-like verbs. The functions and metho
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/plyinteractions/inst/doc/process_pairs.R
// Upstream  : Biostrings, GenomicRanges, plyranges, sessioninfo, tidyverse
// Downstream: none
//
// Install: BiocManager::install("plyinteractions")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PLYINTERACTIONS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-plyinteractions"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-plyinteractions:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-plyinteractions:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_plyinteractions_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_plyinteractions_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_plyinteractions_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAStringSet)
    library(HiContactsData)
    library(jsonlite)

    # --- Hi Contacts Data [] ---
    # Key functions: HiContactsData, set_names, as_ginteractions
    library(tidyverse)
    library(plyinteractions)
    pairs_file <- HiContactsData::HiContactsData('mESCs', 'pairs.gz')
    # --- D N A String Set [] ---
    # Key functions: DNAStringSet, bplapply, matchPattern
    library(GenomicRanges)
    library(Biostrings)
    library(plyranges)
    # --- annotate [] ---
    # Key functions: annotate
    plyinteractions::annotate(fragments, by = "binID") |>
    mutate(n_fragments = binID.2 - binID.1, group = paste0(strand1, strand2))
    # --- Custom ggplot2 visualization [] ---
    # Key functions: group_by, count, as_tibble, ggplot, geom_line
    head(n = 1e6) |>
    group_by(strand1, strand2, n_fragments) |>
    count() |>
    # --- arrange [] ---
    # Key functions: arrange, group_by, ungroup, slice_head, rename
    filter(n_fragments <= 50) |>
    arrange(n_fragments) |>
    group_by(n_fragments) |>
    # --- mcols [] ---
    # Key functions: mcols, as_tibble, count
    mutate(threshold = left_join(as_tibble(mcols(annotated_pairs)), filters)$threshold) |>
    # --- Ps1 [] ---
    # Key functions: group_by, count, as_tibble, ggplot
    mutate(s = abs(end2 - start1)) |>
    group_by(s) |>
    count(name = "n") |>
    # --- Ps3 [] ---
    # Key functions: coef, lead, group_by, count
    Calculate distance breaks evenly spaced on a log scale (base 1.1)
    x <- 1.1^(1:200-1)
    lmc <- coef(lm(c(1,1161443398)~c(x[1], x[200])))
    # --- Ps4 [] ---
    # Key functions: ggplot, geom_line, scale_x_log10, scale_y_log10, annotation_logticks
    ggplot(dat, aes(x = binned_s, y = Ps)) +
    geom_line() +
    scale_x_log10(limits = c(1e3, 1e8)) +    ## This changes x axis to log scale

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_plyinteractions_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_plyinteractions_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_plyinteractions_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PLYINTERACTIONS:", paste0("    plyinteractions: ", packageVersion("plyinteractions"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_plyinteractions_results.csv
    touch ${prefix}_plyinteractions_output.rds
    echo "BIOC_PLYINTERACTIONS:" > versions.yml
    echo "    plyinteractions: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PLYINTERACTIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PLYINTERACTIONS(ch_input)

    emit:
    results  = BIOC_PLYINTERACTIONS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PLYINTERACTIONS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PLYINTERACTIONS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PLYINTERACTIONS.out.versions  // channel: path(versions.yml)
}
