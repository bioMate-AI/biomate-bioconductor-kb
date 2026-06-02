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
    library(plyinteractions)
    library(DNAStringSet)
    library(HiContactsData)
    library(jsonlite)

    # --- Annotate Interactions [] ---
    # Key functions: annotate, mutate
    fragments <- GenomicRanges::GRanges(
        seqnames = "chr1",
        ranges = IRanges::IRanges(start = seq(1, 1000, by = 100), width = 99),
        binID = 1:10
    )
    annotated_pairs <- pairs |> 
        plyinteractions::annotate(fragments, by = "binID") |> 
        mutate(
            n_fragments = binID.2 - binID.1, 
            group = paste0(strand1, strand2)
        )


    # --- Filter Interactions [] ---
    # Key functions: filter, mutate
    filtered_pairs <- annotated_pairs |>
        mutate(type = case_when(
            group %in% c('--', '++') & n_fragments < 5 ~ "excluded",
            group == '+-' & n_fragments < 5 ~ "uncut",
            .default = "kept"
        )) |>
        filter(type == "kept")


    # --- Calculate Interaction Frequency [] ---
    # Key functions: mutate, group_by
    dat <- filtered_pairs |> 
        mutate(s = abs(end2 - start1)) |> 
        group_by(s) |> 
        count(name = "n") |>
        as_tibble() |> 
        mutate(Ps = n / sum(n))

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
