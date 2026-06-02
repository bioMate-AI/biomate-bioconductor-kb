#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: raer
// Toolkit for identification and statistical testing of RNA editing signals from within R. Provides su
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/raer/inst/doc/raer.R
// Upstream  : AnnotationHub, ComplexHeatmap, SingleCellExperiment, raerdata, scater
// Downstream: none
//
// Install: BiocManager::install("raer")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-raer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-raer:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-raer:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_raer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_raer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_raer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(raer)
    library(FilterParam)
    library(jsonlite)

    # --- Single-Cell Editing Frequency Calculation [] ---
    # Key functions: calc_edit_frequency
    e_sce <- e_sce[rowSums(assays(e_sce)$nAlt > 0) >= 5, ]
    e_sce <- calc_edit_frequency(
        e_sce,
        edit_from = "Ref",
        edit_to = "Alt",
        replace_na = FALSE
    )
    altExp(sce) <- e_sce[, colnames(sce)]


    # --- Bulk RNA-Seq Editing Pileup [] ---
    # Key functions: FilterParam, pileup_sites
    fp <- FilterParam(
        only_keep_variants = TRUE,
        trim_5p = 5,
        trim_3p = 5,
        min_base_quality = 30,
        min_mapq = 255,
        library_type = "fr-first-strand",
        min_splice_overhang = 10
    )
    rse <- pileup_sites(
        bam_files,
        fasta = fafn,
        sites = chr_18_editing_sites,
        chroms = "chr18",
        param = fp
    )


    # --- Bulk Editing Frequency and Filtering [] ---
    # Key functions: calc_edit_frequency
    rse <- calc_edit_frequency(
        rse,
        edit_from = "A",
        edit_to = "G",
        drop = TRUE
    )
    has_editing <- rowSums(assay(rse, "edit_freq") > 0) >= 1
    has_depth <- rowSums(assay(rse, "depth") >= 5) == ncol(rse)
    rse <- rse[has_editing & has_depth, ]


    # --- Differential Editing Analysis [] ---
    # Key functions: make_de_object, find_de_sites
    deobj <- make_de_object(
        rse,
        min_prop = 0.05,
        min_samples = 3
    )
    deobj$sample <- factor(deobj$sample)
    de_results <- find_de_sites(
        deobj,
        test = "DESeq2",
        sample_col = "sample",
        condition_col = "genotype",
        condition_control = "Wildtype",
        condition_treatment = "ADAR1KO"
    )


    # --- SNP Annotation and Overlap [] ---
    # Key functions: get_overlapping_snps
    seqlevelsStyle(alus) <- "NCBI"
    genome(alus) <- "GRCh38.p2"
    alu_snps <- get_overlapping_snps(
        alus,
        SNPlocs.Hsapiens.dbSNP144.GRCh38
    )
    seqlevelsStyle(alu_snps) <- "UCSC"

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_raer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_raer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_raer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RAER:", paste0("    raer: ", packageVersion("raer"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_raer_results.csv
    touch ${prefix}_raer_output.rds
    echo "BIOC_RAER:" > versions.yml
    echo "    raer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RAER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RAER(ch_input)

    emit:
    results  = BIOC_RAER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RAER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RAER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RAER.out.versions  // channel: path(versions.yml)
}
