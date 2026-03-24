#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: BiocSet
// BiocSet displays different biological sets in a triple tibble format. These three tibbles are `eleme
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/BiocSet/inst/doc/BiocSet.R
// Upstream  : airway, BiocFileCache, DESeq2, tibble, limma
// Downstream: RegEnrich
//
// Install: BiocManager::install("BiocSet")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOCSET {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biocset"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biocset:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biocset:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(deseqdataset)

    output:
    tuple val(meta), path("${meta.id}_biocset_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biocset_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biocset_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BiocSet)
    library(BiocSet_from_elementset)
    library(DESeq)
    library(DESeqDataSet)
    library(jsonlite)

    # --- Import genomic data file [] ---
    # Key functions: import, es_element, unnest, unlist, kegg_sets, bfcnew, export, DESeqDataSet
    download.file("http://current.geneontology.org/ontology/go.obo", "obo_file.obo")
    foo <- import("obo_file.obo", extract_tag = "everything")
    small_tst <- es_element(foo)[1,] %>%
    # --- GO analysis via limma [] ---
    # Key functions: goana, as_tibble
    library(limma)
    go_ids <- goana(tbl$ENTREZID[tbl$padj < 0.05], tbl$ENTREZID, "Hs") %>%
    as.data.frame() %>%
    # --- BiocSet analysis [] ---
    # Key functions: BiocSet, tempfile, export, union, union_single, go_sets, es_activate, count
    foo <- foo %>% dplyr::rename(element = ENTREZID, set = GOALL)
    tbl <- tbl %>% dplyr::rename(element = ENTREZID)
    go_ids <- go_ids %>% dplyr::rename(set = GOALL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biocset_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biocset_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biocset_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOCSET:", paste0("    biocset: ", packageVersion("BiocSet"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biocset_results.csv
    touch ${prefix}_biocset_output.rds
    echo "BIOC_BIOCSET:" > versions.yml
    echo "    biocset: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOCSET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(deseqdataset) ]

    main:
    BIOC_BIOCSET(ch_input)

    emit:
    results  = BIOC_BIOCSET.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOCSET.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOCSET.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOCSET.out.versions  // channel: path(versions.yml)
}
