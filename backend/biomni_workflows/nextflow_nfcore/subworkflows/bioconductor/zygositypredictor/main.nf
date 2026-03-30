#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ZygosityPredictor
// The ZygosityPredictor allows to predict how many copies of a gene are affected by small variants. In
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ZygosityPredictor/inst/doc/Usage.R
// Upstream  : GenomicRanges, dplyr, stringr
// Downstream: none
//
// Install: BiocManager::install("ZygosityPredictor")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ZYGOSITYPREDICTOR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-zygositypredictor"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-zygositypredictor:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-zygositypredictor:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_zygositypredictor_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_zygositypredictor_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_zygositypredictor_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ZP_ov)
    library(jsonlite)

    # --- Elementmetadata [] ---
    # Key functions: elementMetadata, seqnames, number, subsetByOverlaps, aff_germ_copies
    ---------------------------------------------------------------------
    ## as an example we take the first variant of our prepared input data and
    ## extract the required information from different input data layer
    ## the allele frequency and the chromosome can be taken from the GRanges object
    AF = elementMetadata(GR_GERM_SMALL_VARS[1])[["af"]]
    # --- Elementmetadata [] ---
    # Key functions: elementMetadata, seqnames, subsetByOverlaps, aff_som_copies
    ---------------------------------------------------------------------
    ## the function for somatic variants works the same way as the germline function
    AF = elementMetadata(GR_SOM_SMALL_VARS[1])[["af"]]
    CHR = seqnames(GR_SOM_SMALL_VARS[1]) %>%
      as.character()
    # --- Mergebyoverlaps [] ---
    # Key functions: mergeByOverlaps, as_tibble, select, mutate_at, rowwise, mutate, aff_som_copies
    ---------------------------------------------------------------------
    ## as an example we calculate the affected copies for the somatic variants:
    GR_SOM_SMALL_VARS %>%
      ## cnv information for every variant is required.. merge with cnv object
      IRanges::mergeByOverlaps(GR_SCNA) %>%
    # --- Predict Per Variant [] ---
    # Key functions: predict_per_variant
    ---------------------------------------------------------------------
    predict_per_variant(purity=PURITY,
                        sex=SEX,
                        somCna=GR_SCNA,
                        somSmallVars=GR_SOM_SMALL_VARS)
    # --- Zp Ov [] ---
    # Key functions: ZP_ov
    ---------------------------------------------------------------------
    ZP_ov(fp)
    # --- Gene Ov [] ---
    # Key functions: gene_ov
    ---------------------------------------------------------------------
    gene_ov(fp, OR2J1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_zygositypredictor_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_zygositypredictor_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_zygositypredictor_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ZYGOSITYPREDICTOR:", paste0("    zygositypredictor: ", packageVersion("ZygosityPredictor"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_zygositypredictor_results.csv
    touch ${prefix}_zygositypredictor_output.rds
    echo "BIOC_ZYGOSITYPREDICTOR:" > versions.yml
    echo "    zygositypredictor: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ZYGOSITYPREDICTOR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ZYGOSITYPREDICTOR(ch_input)

    emit:
    results  = BIOC_ZYGOSITYPREDICTOR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ZYGOSITYPREDICTOR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ZYGOSITYPREDICTOR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ZYGOSITYPREDICTOR.out.versions  // channel: path(versions.yml)
}
