#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: metagene2
// This package produces metagene plots to compare coverages of sequencing experiments at selected grou
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/metagene2/inst/doc/metagene2.R
// Upstream  : GenomicFeatures, knitr
// Downstream: none
//
// Install: BiocManager::install("metagene2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METAGENE2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-metagene2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-metagene2:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-metagene2:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_metagene2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_metagene2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_metagene2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(metagene2)
    library(jsonlite)

    # --- bamFiles show [] ---
    # Key functions: get_demo_bam_files
    bam_files <- get_demo_bam_files()
    basename(bam_files)
    # --- get_demo_region_filenames [] ---
    # Key functions: get_demo_region_filenames
    regions <- get_demo_region_filenames()
    # --- grangeslist chipseq regions [] ---
    # Key functions: get_demo_regions
    regions <- get_demo_regions()
    # --- demo rna regions [] ---
    # Key functions: get_demo_rna_regions
    regions <- get_demo_rna_regions()
    # --- design definition [] ---
    # Key functions: kable
    example_design <- data.frame(Samples = bam_files,
    align1 = c(1,1,0,0,2),
    align2 = c(0,0,1,1,2))
    # --- group region grangeslist [] ---
    # Key functions: get_demo_regions
    regions_grl <- get_demo_regions()
    lapply(regions_grl, length)
    # --- group region metadata [] ---
    # Key functions: unlist
    regions_gr <- unlist(get_demo_regions())
    # --- get_demo_metagene [] ---
    # Key functions: get_demo_metagene
    mg <- get_demo_metagene()
    names(mg$get_params())
    mg$get_params()[["bin_count"]]
    # --- get_demo_regions [] ---
    # Key functions: get_demo_regions
    get_demo_regions()
    mg <- metagene2$new(regions = get_demo_regions(),
    bam_files = get_demo_bam_files())
    # --- plot_metagene [] ---
    # Key functions: plot_metagene
    mg1 <- metagene2$new(bam_files = get_demo_bam_files(),
    regions = get_demo_regions()[1])
    # --- metagene heatmap default order [] ---
    # Key functions: get_demo_metagene, metagene2_heatmap
    mg <- get_demo_metagene()
    metagene2_heatmap(mg)
    # --- metagene heatmap decreasing order [] ---
    # Key functions: get_demo_metagene, metagene2_heatmap
    mg <- get_demo_metagene()
    metagene2_heatmap(mg, coverage_order(mg, "align1_rep1"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_metagene2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_metagene2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_metagene2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METAGENE2:", paste0("    metagene2: ", packageVersion("metagene2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metagene2_results.csv
    touch ${prefix}_metagene2_output.rds
    echo "BIOC_METAGENE2:" > versions.yml
    echo "    metagene2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METAGENE2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METAGENE2(ch_input)

    emit:
    results  = BIOC_METAGENE2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METAGENE2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METAGENE2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METAGENE2.out.versions  // channel: path(versions.yml)
}
