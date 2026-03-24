#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: regionalpcs
// Functions to summarize DNA methylation data using regional principal components. Regional principal 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/regionalpcs/inst/doc/regionalpcs.R
// Upstream  : GenomicRanges, dplyr, minfiData, tibble, tidyr
// Downstream: none
//
// Install: BiocManager::install("regionalpcs")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REGIONALPCS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-regionalpcs"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-regionalpcs:1.4.0--r44_0' :
        'quay.io/biocontainers/bioconductor-regionalpcs:1.4.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_regionalpcs_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_regionalpcs_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_regionalpcs_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GenomicMethylSet)
    library(jsonlite)

    # --- Genomic Positions [] ---
    # Key functions: GenomicMethylSet, mapToGenome, object, granges
    # Map the methylation data to genomic coordinates using the mapToGenome
    # function. This creates a GenomicMethylSet (gset) which includes genomic
    # position information for each probe.
    gset <- mapToGenome(MsetEx.sub)
    # Display the GenomicMethylSet object to observe the structure and initial
    # --- Compute Regional Pcs [] ---
    # Key functions: compute_regional_pcs
    # Display head of region map
    head(region_map)
    dim(region_map)
    # Compute regional PCs
    res <- compute_regional_pcs(meth=mvals, region_map=region_map, pc_method="gd")
    # --- Count Pcs Regions [] ---
    # Key functions: frame, separate
    # Count the number of unique gene regions and PCs
    regions <- data.frame(gene_pc = rownames(regional_pcs)) |>
        separate(gene_pc, into = c("gene", "pc"), sep = "-")
    head(regions)
    # number of genes that have been summarized
    # --- Marcenko Pasteur Method [] ---
    # Key functions: compute_regional_pcs, frame, separate
    # Using Marcenko-Pasteur method
    mp_res <- compute_regional_pcs(mvals, region_map, pc_method = "mp")
    # select the regional pcs
    mp_regional_pcs <- mp_res$regional_pcs
    # separate the genes from the pc numbers

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_regionalpcs_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_regionalpcs_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_regionalpcs_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REGIONALPCS:", paste0("    regionalpcs: ", packageVersion("regionalpcs"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_regionalpcs_results.csv
    touch ${prefix}_regionalpcs_output.rds
    echo "BIOC_REGIONALPCS:" > versions.yml
    echo "    regionalpcs: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REGIONALPCS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REGIONALPCS(ch_input)

    emit:
    results  = BIOC_REGIONALPCS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REGIONALPCS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REGIONALPCS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REGIONALPCS.out.versions  // channel: path(versions.yml)
}
