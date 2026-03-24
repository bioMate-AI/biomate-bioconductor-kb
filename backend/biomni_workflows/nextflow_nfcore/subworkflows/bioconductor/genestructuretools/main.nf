#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneStructureTools
// GeneStructureTools can be used to create in silico alternative splicing events, and analyse potentia
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneStructureTools/inst/doc/Vignette.R
// Upstream  : GenomicRanges, Gviz, notNMD, rtracklayer, stringr
// Downstream: none
//
// Install: BiocManager::install("GeneStructureTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENESTRUCTURETOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genestructuretools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genestructuretools:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genestructuretools:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genestructuretools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genestructuretools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genestructuretools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GeneRegionTrack)
    library(GenomeAxisTrack)
    library(UTR2UTR53)
    library(jsonlite)

    # --- Import genomic data file [] ---
    # Key functions: readWhippetDataSet, import, UTR2UTR53, findDEXexonType
    gtf <- rtracklayer::import(system.file("extdata","example_gtf.gtf", package = "GeneStructureTools"))
    leafcutter_files <- list.files(system.file("extdata","leafcutter/", package = "GeneStructureTools"),full.names = TRUE)
    intron_results <- read.delim(leafcutter_files[grep("per_intron_results.tab", leafcutter_files)], stringsAsFactors = FALSE)
    # --- FilterWhippetEvents analysis [] ---
    # Key functions: filterWhippetEvents, whippetTranscriptChangeSummary, diffSplicingResults, coordinates, skipExonInTranscript, GenomeAxisTrack, GeneRegionTrack, plotTracks
    upstreamORFs <- getUOrfs(normalTranscripts, BSgenome = g, orfs=orfs_normal, findExonB=TRUE)
    head(upstreamORFs)
    overlaps_main_orf: is the entire uorf upstream of the main orf (upstream), or is there  some overlap with the main orf (downsteam) - i.e. uORF stop codon is within the main ORF

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genestructuretools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genestructuretools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genestructuretools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENESTRUCTURETOOLS:", paste0("    genestructuretools: ", packageVersion("GeneStructureTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genestructuretools_results.csv
    touch ${prefix}_genestructuretools_output.rds
    echo "BIOC_GENESTRUCTURETOOLS:" > versions.yml
    echo "    genestructuretools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENESTRUCTURETOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENESTRUCTURETOOLS(ch_input)

    emit:
    results  = BIOC_GENESTRUCTURETOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENESTRUCTURETOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENESTRUCTURETOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENESTRUCTURETOOLS.out.versions  // channel: path(versions.yml)
}
