#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: wiggleplotr
// Tools to visualise read coverage from sequencing experiments together with genomic annotations (gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/wiggleplotr/inst/doc/wiggleplotr.R
// Upstream  : GenomicFeatures, GenomicRanges, biomaRt, dplyr, ensembldb
// Downstream: none
//
// Install: BiocManager::install("wiggleplotr")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_WIGGLEPLOTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-wiggleplotr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-wiggleplotr:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-wiggleplotr:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_wiggleplotr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_wiggleplotr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_wiggleplotr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(wiggleplotr)
    library(jsonlite)

    # --- Plottranscripts [] ---
    # Key functions: plotTranscripts
    ---------------------------------------------------------------------
    plotTranscripts(ncoa7_exons, ncoa7_cdss, ncoa7_metadata, rescale_introns = FALSE)
    # --- Data Frame [] ---
    # Key functions: data_frame, factor, mutate, frame
    ---------------------------------------------------------------------
    sample_data = dplyr::data_frame(
      sample_id = c("aipt_A", "aipt_C", "bima_A", "bima_C"),
      condition = factor(c("Naive", "LPS", "Naive", "LPS"), levels = c("Naive", "LPS")),
      scaling_factor = 1)
    # --- Mutate [] ---
    # Key functions: mutate
    ---------------------------------------------------------------------
    track_data = dplyr::mutate(sample_data, track_id = condition, colour_group = condition)
    # --- Plotcoverage [] ---
    # Key functions: plotCoverage, getGenotypePalette
    ---------------------------------------------------------------------
    plotCoverage(ncoa7_exons[selected_transcripts], ncoa7_cdss[selected_transcripts],
                 ncoa7_metadata, track_data,
                 heights = c(2,1), fill_palette = getGenotypePalette(), mean_only = FALSE, alpha = 0.5)
    # --- Mutate [] ---
    # Key functions: mutate, plotCoverage, getGenotypePalette
    ---------------------------------------------------------------------
    track_data = dplyr::mutate(sample_data, track_id = "RNA-seq", colour_group = condition)
    plotCoverage(ncoa7_exons[selected_transcripts], ncoa7_cdss[selected_transcripts],
                ncoa7_metadata, track_data,
                 heights = c(2,1), fill_palette = getGenotypePalette(), coverage_type = "line")
    # --- Plottranscriptsfromensembldb [] ---
    # Key functions: plotTranscriptsFromEnsembldb
    ---------------------------------------------------------------------
    library("ensembldb")
    library("EnsDb.Hsapiens.v86")
    plotTranscriptsFromEnsembldb(EnsDb.Hsapiens.v86, gene_names = "NCOA7",
                                 transcript_ids = c("ENST00000438495", "ENST00000392477"))
    # --- Plottranscriptsfromucsc [] ---
    # Key functions: plotTranscriptsFromUCSC
    ---------------------------------------------------------------------
    #Load OrgDb and TxDb objects with UCSC gene annotations
    require("org.Hs.eg.db")
    require("TxDb.Hsapiens.UCSC.hg38.knownGene")
    # --- Usemart [] ---
    # Key functions: useMart, useDataset
    ---------------------------------------------------------------------
    ensembl_mart = useMart("ENSEMBL_MART_ENSEMBL", host = "jan2020.archive.ensembl.org")
    ensembl_dataset = useDataset("hsapiens_gene_ensembl",mart=ensembl_mart)
    ensembl_dataset
    # --- Listattributes [] ---
    # Key functions: listAttributes
    ---------------------------------------------------------------------
    attributes = listAttributes(ensembl_dataset)
    head(attributes)
    # --- Rename [] ---
    # Key functions: rename
    ---------------------------------------------------------------------
    data = dplyr::rename(data,
                         transcript_id = ensembl_transcript_id,
                         gene_id = ensembl_gene_id,
                         gene_name = external_gene_name)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_wiggleplotr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_wiggleplotr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_wiggleplotr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_WIGGLEPLOTR:", paste0("    wiggleplotr: ", packageVersion("wiggleplotr"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_wiggleplotr_results.csv
    touch ${prefix}_wiggleplotr_output.rds
    echo "BIOC_WIGGLEPLOTR:" > versions.yml
    echo "    wiggleplotr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_WIGGLEPLOTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_WIGGLEPLOTR(ch_input)

    emit:
    results  = BIOC_WIGGLEPLOTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_WIGGLEPLOTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_WIGGLEPLOTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_WIGGLEPLOTR.out.versions  // channel: path(versions.yml)
}
