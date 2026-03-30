#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Organism.dplyr
// This package provides an alternative interface to Bioconductor 'annotation' resources, in particular
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Organism.dplyr/inst/doc/Organism.dplyr.R
// Upstream  : GenomicRanges, ggplot2
// Downstream: annotation
//
// Install: BiocManager::install("Organism.dplyr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ORGANISM_DPLYR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-organism_dplyr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-organism.dplyr:1.34.0--r44_0' :
        'quay.io/biocontainers/bioconductor-organism.dplyr:1.34.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_organism_dplyr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_organism_dplyr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_organism_dplyr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AnnotationFilterList)
    library(EnsemblFilter)
    library(GRanges)
    library(GRangesFilter)
    library(SymbolFilter)
    library(TxEndFilter)
    library(TxStartFilter)
    library(jsonlite)

    # --- Supportedorganisms [] ---
    # Key functions: supportedOrganisms
    ---------------------------------------------------------------------
    supportedOrganisms()
    # --- Src Organism [] ---
    # Key functions: src_organism, hg38light
    ---------------------------------------------------------------------
    src <- src_organism(dbpath = hg38light())
    src
    # --- Src Tbls [] ---
    # Key functions: src_tbls
    ---------------------------------------------------------------------
    src_tbls(src)
    # --- Tbl [] ---
    # Key functions: tbl
    ---------------------------------------------------------------------
    tbl(src, "id")
    # --- Colnames [] ---
    # Key functions: tbl
    ---------------------------------------------------------------------
    colnames(tbl(src, "id"))
    # --- Tbl [] ---
    # Key functions: tbl, filter, select, distinct, arrange, collect
    ---------------------------------------------------------------------
    tbl(src, "id") %>%
        filter(symbol %like% "SNORD%") %>%
        dplyr::select(entrez, map, ensembl, symbol) %>%
        distinct() %>% arrange(symbol) %>% collect()
    # --- Inner Join [] ---
    # Key functions: inner_join, tbl, filter, select
    ---------------------------------------------------------------------
    inner_join(tbl(src, "id"), tbl(src, "id_go")) %>%
        filter(symbol == "ADA") %>%
        dplyr::select(entrez, ensembl, symbol, go, evidence, ontology)
    # --- Inner Join [] ---
    # Key functions: inner_join, tbl, select, group_by, summarize, n, arrange, desc
    ---------------------------------------------------------------------
    txcount <- inner_join(tbl(src, "id"), tbl(src, "ranges_tx")) %>%
        dplyr::select(symbol, tx_id) %>%
        group_by(symbol) %>%
        summarize(count = n()) %>%
    # --- Inner Join [] ---
    # Key functions: inner_join, tbl, filter, select, collect, GRanges
    ---------------------------------------------------------------------
    inner_join(tbl(src, "id"), tbl(src, "ranges_gene")) %>%
        filter(symbol %in% c("ADA", "NAT2")) %>%
        dplyr::select(gene_chrom, gene_start, gene_end, gene_strand,
                      symbol, map) %>%
    # --- Keytypes [] ---
    # Key functions: keytypes
    ---------------------------------------------------------------------
    keytypes(src)
    # --- Columns [] ---
    # Key functions: columns
    ---------------------------------------------------------------------
    columns(src)
    # --- Head [] ---
    # Key functions: keys
    ---------------------------------------------------------------------
    head(keys(src))
    # --- Mapids [] ---
    # Key functions: mapIds
    ---------------------------------------------------------------------
    mapIds(src, keys, column = "tx_name", keytype)
    mapIds(src, keys, column = "tx_name", keytype, multiVals="CharacterList")
    # --- Supportedfilters [] ---
    # Key functions: supportedFilters
    ---------------------------------------------------------------------
    supportedFilters(src)
    # --- Ensemblfilter [] ---
    # Key functions: EnsemblFilter, SymbolFilter
    ---------------------------------------------------------------------
    EnsemblFilter("ENSG00000196839")
    SymbolFilter("SNORD", "startsWith")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_organism_dplyr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_organism_dplyr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_organism_dplyr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ORGANISM_DPLYR:", paste0("    organism_dplyr: ", packageVersion("Organism.dplyr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_organism_dplyr_results.csv
    touch ${prefix}_organism_dplyr_output.rds
    echo "BIOC_ORGANISM_DPLYR:" > versions.yml
    echo "    organism_dplyr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ORGANISM_DPLYR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ORGANISM_DPLYR(ch_input)

    emit:
    results  = BIOC_ORGANISM_DPLYR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ORGANISM_DPLYR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ORGANISM_DPLYR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ORGANISM_DPLYR.out.versions  // channel: path(versions.yml)
}
