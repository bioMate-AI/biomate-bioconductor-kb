#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MSnID
// Extracts MS/MS ID data from mzIdentML (leveraging mzID package) or text files. After collating the s
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MSnID/inst/doc/handling_mods.R
// Upstream  : Biostrings, MSnbase, dplyr, ggplot2, xtable
// Downstream: none
//
// Install: BiocManager::install("MSnID")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSNID {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msnid"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msnid:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msnid:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msnid_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msnid_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msnid_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MSnID)
    library(jsonlite)

    # --- Msnid [] ---
    # Key functions: MSnID, read_mzIDs
    m <- MSnID(".")
    mzids <- system.file("extdata","phospho.mzid.gz",package="MSnID")
    m <- read_mzIDs(m, mzids)
    # --- Report Mods [] ---
    # Key functions: report_mods
    # to know the present mod masses
    report_mods(m)
    # --- Add Mod Symbol [] ---
    # Key functions: add_mod_symbol, psms, distinct
    m <- add_mod_symbol(m, mod_mass="79.966330925", symbol="*")
    x <- psms(m) %>%
        distinct(modification, peptide, peptide_mod)
    # --- Xtable [] ---
    # Key functions: xtable, align
    x <- x %>%
        `[`(sel_idx,) %>%
        xtable()
    align(x) <- "lp{1.8in}p{1.8in}p{1.8in}"
    print(x,
    # --- Map Mod Sites [] ---
    # Key functions: map_mod_sites, psms, distinct
    m <- map_mod_sites(m, fst,
                       accession_col = "accession",
                       peptide_mod_col = "peptide_mod",
                       mod_char = "*",
                       site_delimiter = "lower")
    # --- Xtable [] ---
    # Key functions: xtable, align
    x <- x %>%
        `[`(sel_idx,) %>%
        xtable()
    align(x) <- "lp{1.8in}p{3.6in}"
    print(x,
    # --- Fetch Conversion Table [] ---
    # Key functions: fetch_conversion_table
    conv_tab <- fetch_conversion_table("Homo sapiens", "UNIPROT", "SYMBOL")
    head(conv_tab)
    # --- Head [] ---
    # Key functions: accessions, remap_accessions
    head(accessions(m))
    m <- remap_accessions(m, conv_tab, extraction_pttrn = "\\|([^|-]+)(-\\d+)?\\|")
    head(accessions(m))
    # --- Readaastringset [] ---
    # Key functions: readAAStringSet, map_mod_sites, psms, distinct
    fst <- readAAStringSet(fst_path_2)
    m <- map_mod_sites(m, fst,
                       accession_col = "accession",
                       peptide_mod_col = "peptide_mod",
                       mod_char = "*",
    # --- Xtable [] ---
    # Key functions: xtable, align
    x <- x %>%
        `[`(sel_idx,) %>%
        xtable()
    align(x) <- "lp{1.8in}p{3.6in}"
    print(x,
    # --- Unlink [] ---
    # Key functions: unlink
    unlink(".Rcache", recursive=TRUE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msnid_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msnid_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msnid_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSNID:", paste0("    msnid: ", packageVersion("MSnID"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msnid_results.csv
    touch ${prefix}_msnid_output.rds
    echo "BIOC_MSNID:" > versions.yml
    echo "    msnid: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSNID_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSNID(ch_input)

    emit:
    results  = BIOC_MSNID.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSNID.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSNID.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSNID.out.versions  // channel: path(versions.yml)
}
