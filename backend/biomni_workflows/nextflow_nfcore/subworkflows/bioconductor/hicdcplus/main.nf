#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiCDCPlus
// Systematic 3D interaction calls and differential analysis for Hi-C and HiChIP. The HiC-DC+ (Hi-C/HiC
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiCDCPlus/inst/doc/HiCDCPlus.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("HiCDCPlus")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HICDCPLUS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hicdcplus"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hicdcplus:1.14.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hicdcplus:1.14.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hicdcplus_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hicdcplus_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hicdcplus_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HiCDCPlus)
    library(jsonlite)

    # --- Data Import and Count Addition [] ---
    # Key functions: generate_bintolen_gi_list, add_hic_counts
    hicfile_path <- system.file(
        "extdata", "GSE63525_HMEC_combined_example.hic",
        package = "HiCDCPlus"
    )
    gi_list <- generate_bintolen_gi_list(
        bintolen_path = paste0(outdir, "/hg19_50kb_GATC_bintolen.txt.gz")
    )
    gi_list <- add_hic_counts(gi_list, hic_path = hicfile_path)


    # --- Normalisation and Modeling [] ---
    # Key functions: expand_1D_features, HiCDCPlus, hicdc2hic, gi_list_write
    gi_list <- expand_1D_features(gi_list)
    gi_list <- HiCDCPlus(gi_list)
    hicdc2hic(
        gi_list,
        hicfile = paste0(outdir, "/GSE63525_HMEC_combined_result.hic"),
        mode = "normcounts", gen_ver = "hg19"
    )
    gi_list_write(
        gi_list,
        fname = paste0(outdir, "/GSE63525_HMEC_combined_result.txt.gz")
    )


    # --- Differential Analysis [] ---
    # Key functions: hicdcdiff
    hicdcdiff(
        input_paths = list(
            NSD2 = c(
                paste0(outdir, "/GSE131651_NSD2_LOW_arima_example.txt.gz"),
                paste0(outdir, "/GSE131651_NSD2_HIGH_arima_example.txt.gz")
            ),
            TKO = c(
                paste0(outdir, "/GSE131651_TKOCTCF_new_example.txt.gz"),
                paste0(outdir, "/GSE131651_NTKOCTCF_new_example.txt.gz")
            )
        ),
        filter_file = paste0(outdir, "/GSE131651_analysis_indices.txt.gz"),
        output_path = paste0(outdir, "/diff_analysis_example/"),
        fitType = "mean", chrs = "chr22", binsize = 50000,
        diagnostics = TRUE
    )


    # --- ICE Normalisation and TAD Calling [] ---
    # Key functions: hic2icenorm_gi_list, gi_list_topdom
    hic_path <- system.file(
        "extdata", "GSE63525_HMEC_combined_example.hic",
        package = "HiCDCPlus"
    )
    gi_list <- hic2icenorm_gi_list(
        hic_path, binsize = 50000, chrs = c("chr22"),
        Dthreshold = 400000
    )
    tads <- gi_list_topdom(gi_list, chrs = c("chr22"), window.size = 10)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hicdcplus_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hicdcplus_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hicdcplus_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HICDCPLUS:", paste0("    hicdcplus: ", packageVersion("HiCDCPlus"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hicdcplus_results.csv
    touch ${prefix}_hicdcplus_output.rds
    echo "BIOC_HICDCPLUS:" > versions.yml
    echo "    hicdcplus: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HICDCPLUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HICDCPLUS(ch_input)

    emit:
    results  = BIOC_HICDCPLUS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HICDCPLUS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HICDCPLUS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HICDCPLUS.out.versions  // channel: path(versions.yml)
}
