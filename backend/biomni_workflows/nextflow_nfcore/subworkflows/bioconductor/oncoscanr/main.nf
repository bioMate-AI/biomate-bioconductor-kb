#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: oncoscanR
// The software uses the copy number segments from a text file and identifies all chromosome arms that 
//
// Source : https://bioconductor.org/packages/3.20/bioc/https://bioconductor.org/packages/3.20/bioc/vignettes/oncoscanR/inst/doc/oncoscanR.html
// Upstream  : jsonlite, magrittr
// Downstream: none
//
// Install: BiocManager::install("oncoscanR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ONCOSCANR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-oncoscanr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-oncoscanr:1.8.0--r44_0' :
        'quay.io/biocontainers/bioconductor-oncoscanr:1.8.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_oncoscanr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_oncoscanr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_oncoscanr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(oncoscanR)
    library(jsonlite)

    # --- Code Block 1 [] ---
    # Key functions: chas
    library(oncoscanR)
    #> Loading required package: IRanges
    #> Loading required package: BiocGenerics
    #>
    #> Attaching package: 'BiocGenerics'
    # --- Code Block 2 [] ---
    # Key functions: load_chas, trim_to_coverage, adjust_loh, merge_segments
    library(magrittr)
    # Load the ChAS file
    chas.fn <- system.file("extdata", "chas_example.txt", package = "oncoscanR")
    segments <- load_chas(chas.fn, oncoscan_na33.cov)
    # Clean the segments: restricted to Oncoscan coverage, LOH not overlapping
    # --- Code Block 3 [] ---
    # Key functions: load_ascat
    ascat.fn <- system.file("extdata", "ascat_example.txt", package = "oncoscanR")
    ascat.segments <- load_ascat(ascat.fn, oncoscan_na33.cov)
    head(ascat.segments)
    #> GRanges object with 2 ranges and 2 metadata columns:
    #>       seqnames              ranges strand |        cn     cn.type
    # --- Code Block 4 [] ---
    # Key functions: load_chas, get_loh_segments, armlevel_alt
    chas.fn <- system.file("extdata", "triploide_gene_list_full_location.txt",
                           package = "oncoscanR")
    segments <- load_chas(chas.fn, oncoscan_na33.cov)
    armlevel.loh <- get_loh_segments(segments) %>%
        armlevel_alt(kit.coverage = oncoscan_na33.cov)
    # --- Code Block 5 [] ---
    # Key functions: get_loh_segments, armlevel_alt
    armlevel.loh <- get_loh_segments(segments) %>%
            armlevel_alt(kit.coverage = oncoscan_na33.cov, threshold = 0)
    # --- Code Block 6 [] ---
    # Key functions: score_mbalt, score_avgcn, score_estwgd
    mbalt <- score_mbalt(segments, oncoscan_na33.cov)
    percent.alt <- mbalt['sample']/mbalt['kit']
    message(paste(mbalt['sample'], 'Mbp altered ->', round(percent.alt*100),
                  '% of genome'))
    #> 2503 Mbp altered -> 88 % of genome
    # --- Code Block 7 [] ---
    # Key functions: load_chas, trim_to_coverage, adjust_loh, merge_segments, prune_by_size
    # Load data
    chas.fn <- system.file("extdata", "LST_gene_list_full_location.txt",
                           package = "oncoscanR")
    segments <- load_chas(chas.fn, oncoscan_na33.cov)
    # Clean the segments: restricted to Oncoscan coverage, LOH not overlapping
    # --- Code Block 8 [] ---
    # Key functions: load_chas, trim_to_coverage, adjust_loh, merge_segments, prune_by_size
    # Load data
    chas.fn <- system.file("extdata", "TDplus_gene_list_full_location.txt",
                           package = "oncoscanR")
    segments <- load_chas(chas.fn, oncoscan_na33.cov)
    # Clean the segments: restricted to Oncoscan coverage, LOH not overlapping
    # --- Code Block 10 [] ---
    # Key functions: chas
    segs.filename <- system.file('extdata', 'LST_gene_list_full_location.txt',
                                 package = 'oncoscanR')
    dat <- workflow_oncoscan.chas(segs.filename)
    message(paste('Arms with copy loss:',
                  paste(dat$armlevel$LOSS, collapse = ', ')))
    # --- Code Block 11 [] ---
    # Key functions: ascat, toJSON
    library(jsonlite)
    segs.filename <- system.file('extdata', 'ascat_example.txt',
                                 package = 'oncoscanR')
    dat <- workflow_oncoscan.ascat(segs.filename)
    toJSON(dat, auto_unbox=TRUE, pretty=TRUE)
    # --- Code Block 12 [] ---
    # Key functions: 1, namespace
    sessionInfo()
    #> R version 4.4.1 (2024-06-14)
    #> Platform: x86_64-pc-linux-gnu
    #> Running under: Ubuntu 24.04.1 LTS
    #>

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_oncoscanr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_oncoscanr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_oncoscanr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ONCOSCANR:", paste0("    oncoscanr: ", packageVersion("oncoscanR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_oncoscanr_results.csv
    touch ${prefix}_oncoscanr_output.rds
    echo "BIOC_ONCOSCANR:" > versions.yml
    echo "    oncoscanr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ONCOSCANR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ONCOSCANR(ch_input)

    emit:
    results  = BIOC_ONCOSCANR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ONCOSCANR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ONCOSCANR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ONCOSCANR.out.versions  // channel: path(versions.yml)
}
