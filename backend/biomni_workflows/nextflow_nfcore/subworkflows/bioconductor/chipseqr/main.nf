#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ChIPseqR
// ChIPseqR identifies protein binding sites from ChIP-seq and nucleosome positioning experiments. The 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ChIPseqR/inst/doc/Introduction.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("ChIPseqR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CHIPSEQR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-chipseqr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-chipseqr:1.60.0--r44_0' :
        'quay.io/biocontainers/bioconductor-chipseqr:1.60.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_chipseqr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_chipseqr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_chipseqr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ChIPseqR)
    library(jsonlite)

    # --- Distances [] ---
    # Key functions: sample, dnbinom
    set.seed(1)
    	dist <- sample(c(170:300, 400), 10100, prob=c(dnbinom(0:130, mu=30, size=5), 0.2), replace=TRUE)
    	pos <- cumsum(dist)
    	pos <- pos[pos < 2e6 - 200]
    # --- Readpos1 [] ---
    # Key functions: unlist
    fwdRegion <- unlist(lapply(pos, function(x) (x-88):(x-68)))
    	revRegion <- unlist(lapply(pos, function(x) (x+68):(x+88)))
    # --- Readpos2 [] ---
    # Key functions: sample
    fwd <- sample(fwdRegion, 5e4, replace=TRUE)
    	rev <- sample(revRegion, 5e4, replace=TRUE)
    # --- Readpos3 [] ---
    # Key functions: sample
    fwd <- c(fwd, sample(25:(2e6-25), 2e5, replace=TRUE))
    	rev <- c(rev, sample(25:(2e6-25), 2e5, replace=TRUE))
    # --- Formatdata [] ---
    # Key functions: frame
    reads <- data.frame(chromosome="chr1", position=c(fwd, rev), length=25,
    			strand=rep(c("+", "-"), each=250000))
    # --- Simple [] ---
    # Key functions: strandPileup, simpleNucCall
    counts <- strandPileup(reads, chrLen=2e6, extend=1, plot=FALSE)
    	nucs <- simpleNucCall(counts, bind=147, support=15, plot=FALSE)
    # --- Plotwindowprint [] ---
    # Key functions: peaks
    ## 	predicted <- peaks(nucs)[[1]][911]
    ## 	plot(counts, chr="chr1", center=predicted, score=nucs, width=1000, type="window")
    # --- Plotwindow [] ---
    # Key functions: peaks
    predicted <- peaks(nucs)[[1]][911]
    	plot(counts, chr="chr1", center=predicted, score=nucs, width=1000, type="window")
    	abline(v=pos[pos < predicted + 1000 & pos > predicted - 1000], col=3, lty=3)
    # --- Noover [] ---
    # Key functions: peaks, diff
    calls <- peaks(nucs)[[1]][c(1,which(diff(peaks(nucs)[[1]]) >= 170)+1)]
    	length(calls)
    # --- Getbindlen [] ---
    # Key functions: getBindLen
    bLen <- getBindLen(counts, bind = c(100,200), support = c(5, 50))
    # --- Getbindlenprint [] ---
    # Key functions: getBindLen
    ## 	bLen <- getBindLen(counts, bind = c(100,200), support = c(5, 50))
    # --- Decompress [] ---
    # Key functions: decompress
    counts2 <- decompress(counts)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_chipseqr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_chipseqr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_chipseqr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CHIPSEQR:", paste0("    chipseqr: ", packageVersion("ChIPseqR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_chipseqr_results.csv
    touch ${prefix}_chipseqr_output.rds
    echo "BIOC_CHIPSEQR:" > versions.yml
    echo "    chipseqr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CHIPSEQR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_CHIPSEQR(ch_input)

    emit:
    results  = BIOC_CHIPSEQR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CHIPSEQR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CHIPSEQR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CHIPSEQR.out.versions  // channel: path(versions.yml)
}
