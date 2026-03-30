#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DuplexDiscovereR
// DuplexDiscovereR is a package designed for analyzing data from RNA cross-linking and proximity ligat
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DuplexDiscovereR/inst/doc/DuplexDiscovereR.R
// Upstream  : Gviz, UpSetR, devtools
// Downstream: none
//
// Install: BiocManager::install("DuplexDiscovereR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DUPLEXDISCOVERER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-duplexdiscoverer"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-duplexdiscoverer:1.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-duplexdiscoverer:1.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_duplexdiscoverer_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_duplexdiscoverer_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_duplexdiscoverer_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DuplexTrack)
    library(GRanges)
    library(GeneRegionTrack)
    library(jsonlite)

    # --- run Duplex Discoverer [] ---
    # Key functions: runDuplexDiscoverer
    result <- DuplexDiscovereR::runDuplexDiscoverer(
    # --- observe results2 [] ---
    # Key functions: dd_get_duplex_groups
    gi_clusters <- dd_get_duplex_groups(result)
    head(gi_clusters, 2)
    # --- observe results3 [] ---
    # Key functions: dd_get_chimeric_reads
    gi_reads <- dd_get_chimeric_reads(result)
    head(gi_reads, 2)
    # --- observe results4a [] ---
    # Key functions: dd_get_reads_classes
    df_reads <- dd_get_reads_classes(result)
    print(dim(df_reads))
    print(dim(RNADuplexesRawChimSTAR))
    # --- make Df From Gi [] ---
    # Key functions: makeDfFromGi
    clusters_dt <- makeDfFromGi(gi_clusters)
    write.table(clusters_dt, file = tempfile(pattern = "dgs_out", fileext = ".tab"))
    # --- write Gi To S A Mfile [] ---
    # Key functions: writeGiToSAMfile
    writeGiToSAMfile(gi_clusters, file_out = tempfile(pattern = "dgs_out", fileext = ".sam"), genome = "hg38")
    # --- vis 1 [] ---
    # Key functions: GRanges, GeneRegionTrack, DuplexTrack, plotTracks
    library(Gviz)
    plotrange <- GRanges(
    ranges = IRanges(
    # --- sample [] ---
    # Key functions: sample
    clust_reads <- clust_reads[!is.na(clust_reads$dg_id)]
    set.seed(123)
    group_indices <- sample(rep(1:3, length.out = length(clust_reads)))
    # --- collapse_duplex_groups [] ---
    # Key functions: collapse_duplex_groups
    group1 <- collapse_duplex_groups(group1)
    group2 <- collapse_duplex_groups(group2)
    group3 <- collapse_duplex_groups(group3)
    # --- compare Multiple Interactions [] ---
    # Key functions: compareMultipleInteractions
    a <- list("sample1" = group1, "sample2" = group2, "sample3" = group3)
    res_comp <- compareMultipleInteractions(a)
    names(res_comp)
    # --- upset [] ---
    # Key functions: upset
    if (!requireNamespace("UpSetR", quietly = TRUE)) {
    stop("Install 'UpSetR' to use this function.")
    library(UpSetR)
    # --- preproc ex1 [] ---
    # Key functions: runDuplexDiscoPreproc
    data("RNADuplexesSampleData")
    new_star <- runDuplexDiscoPreproc(
    # --- preproc ex2 [] ---
    # Key functions: runDuplexDiscoPreproc
    new_bedpe <- runDuplexDiscoPreproc(
    # --- preproc ex3 [] ---
    # Key functions: mcols, runDuplexDiscoPreproc
    mcols(RNADuplexSampleGI) <- mcols(RNADuplexSampleGI)["readname"]
    new_gi <- runDuplexDiscoPreproc(data = RNADuplexSampleGI, return_gi = TRUE)
    head(new_gi, 1)
    # --- ex classif1 [] ---
    # Key functions: getChimericJunctionTypes, getSpliceJunctionChimeras
    gi <- getChimericJunctionTypes(new_gi)
    gi <- getSpliceJunctionChimeras(gi, sj_gr = SampleSpliceJncGR)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_duplexdiscoverer_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_duplexdiscoverer_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_duplexdiscoverer_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DUPLEXDISCOVERER:", paste0("    duplexdiscoverer: ", packageVersion("DuplexDiscovereR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_duplexdiscoverer_results.csv
    touch ${prefix}_duplexdiscoverer_output.rds
    echo "BIOC_DUPLEXDISCOVERER:" > versions.yml
    echo "    duplexdiscoverer: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DUPLEXDISCOVERER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DUPLEXDISCOVERER(ch_input)

    emit:
    results  = BIOC_DUPLEXDISCOVERER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DUPLEXDISCOVERER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DUPLEXDISCOVERER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DUPLEXDISCOVERER.out.versions  // channel: path(versions.yml)
}
