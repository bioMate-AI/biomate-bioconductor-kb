#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ADaCGH2
// Analysis and plotting of array CGH data. Allows usage of Circular Binary Segementation, wavelet-base
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ADaCGH2/inst/doc/ADaCGH2.R
// Upstream  : CGHregions, limma
// Downstream: none
//
// Install: BiocManager::install("ADaCGH2")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ADACGH2 {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-adacgh2"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-adacgh2:2.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-adacgh2:2.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_adacgh2_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_adacgh2_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_adacgh2_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CGHregions)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: data
    library(ADaCGH2)
    data(inputEx)
    summary(inputEx)
    head(inputEx)
    # --- Files [] ---
    # Key functions: files, inputToADaCGH
    fnameRdata <- list.files(path = system.file("data", package = "ADaCGH2"),
                         full.names = TRUE, pattern = "inputEx.RData")
    inputToADaCGH(ff.or.RAM = "RAM",
                          RDatafilename = fnameRdata)
    # --- Data [] ---
    # Key functions: inputToADaCGH
    data(inputEx) ## make inputEx available as a data frame with that name
    inputToADaCGH(ff.or.RAM = "RAM",
                          dataframe = inputEx)
    # --- Files [] ---
    # Key functions: files, inputToADaCGH
    fnametxt <- list.files(path = system.file("data", package = "ADaCGH2"),
                             full.names = TRUE, pattern = "inputEx.txt")
    ##    You might want to adapt mc.cores to your hardware
    tmp <- inputToADaCGH(ff.or.RAM = "RAM",
                         textfilename = fnametxt,
    # --- Psegmenthaarseg [] ---
    # Key functions: pSegmentHaarSeg
    ##    You might want to adapt mc.cores to your hardware
    haar.RAM.fork <- pSegmentHaarSeg(cgh.dat, chrom.dat,
                                       merging = "MAD",
                                     typeParall = "fork",
                                     mc.cores = 2)
    # --- Pchromplot [] ---
    # Key functions: pChromPlot
    ##    You might want to adapt mc.cores to your hardware
    pChromPlot(haar.RAM.fork,
               cghRDataName = cgh.dat,
               chromRDataName = chrom.dat,
               posRDataName = pos.dat,
    # --- Mcparallel [] ---
    # Key functions: mcparallel, inputToADaCGH, mccollect, inherits
    ## mcparallel(inputToADaCGH(ff.or.RAM = "ff",
    ##                                  RDatafilename = fnameRData),
    ##                                  silent = FALSE)
    ##   tableChromArray <- mccollect()
    ##   if(inherits(tableChromArray, "try-error")) {
    # --- Mcparallel [] ---
    # Key functions: mcparallel, inputToADaCGH, collect, inherits
    ## mcparallel(inputToADaCGH(ff.or.RAM = "ff",
    ##                                  RDatafilename = fnameRdata),
    ##            silent = FALSE)
    ## tableChromArray <- collect()
    ## if(inherits(tableChromArray, "try-error")) {
    # --- Chunk0001 [] ---
    # Key functions: inputToADaCGH
    if(.Platform$OS.type != "windows") {
    ## You might want to adapt mc.cores to your hardware
    inputToADaCGH(ff.or.RAM = "ff",
                  path = cuttedFile.dir,
                  verbose = TRUE,
    # --- Chunk0002 [] ---
    # Key functions: pSegmentHaarSeg
    if(.Platform$OS.type != "windows") {
    ## You might want to adapt mc.cores to your hardware
    haar.ff.fork <- pSegmentHaarSeg("cghData.RData",
                                    "chromData.RData",
                                     merging = "MAD",
    # --- Chunk0003 [] ---
    # Key functions: pChromPlot
    if(.Platform$OS.type != "windows") {
    save(haar.ff.fork, file = "haar.ff.fork.RData", compress = FALSE)
    ##    You might want to adapt mc.cores to your hardware
    pChromPlot(outRDataName = "haar.ff.fork.RData",
               cghRDataName = "cghData.RData",
    # --- Chunk0006 [] ---
    # Key functions: readTargets, maimages, backgroundCorrect, normalizeWithinArrays
    ## if(.Platform$OS.type != "windows") {
    ##   require("limma")
    ##   datadir <- system.file("testdata", package = "snapCGH")
    ##   targets.limma <- readTargets("targets.txt", path = datadir)
    ##   RG.limma <- read.maimages(targets.limma, path = datadir,
    # --- Chunk0007 [] ---
    # Key functions: files, inputToADaCGH
    ## if(.Platform$OS.type != "windows") {
    ## fclone <- list.files(path = system.file("testdata", package = "snapCGH"),
    ##                      full.names = TRUE, pattern = "cloneinfo.txt")
    ## fclone
    ## tmp <- inputToADaCGH(MAList = MA.limma,
    # --- Chunk0008 [] ---
    # Key functions: inputToADaCGH
    ## if(.Platform$OS.type != "windows") {
    ## acloneinfo <- MA$genes
    ## tmp <- inputToADaCGH(MAList = MA.limma,
    ##                              cloneinfo = acloneinfo,
    ##                              robjnames = c("cgh-ma.dat", "chrom-ma.dat",
    # --- Chunk0009 [] ---
    # Key functions: outputToCGHregions, CGHregions, omit
    if(.Platform$OS.type != "windows") {
    forcghr <- outputToCGHregions(haar.ff.cluster)
    if(require(CGHregions)) {
      regions1 <- CGHregions(na.omit(forcghr))
      regions1

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_adacgh2_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_adacgh2_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_adacgh2_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ADACGH2:", paste0("    adacgh2: ", packageVersion("ADaCGH2"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_adacgh2_results.csv
    touch ${prefix}_adacgh2_output.rds
    echo "BIOC_ADACGH2:" > versions.yml
    echo "    adacgh2: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ADACGH2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ADACGH2(ch_input)

    emit:
    results  = BIOC_ADACGH2.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ADACGH2.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ADACGH2.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ADACGH2.out.versions  // channel: path(versions.yml)
}
