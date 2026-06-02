#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biovizBase
// The biovizBase package is designed to provide a set of utilities, color schemes and conventions for 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biovizBase/inst/doc/intro.R
// Upstream  : GenomicRanges, Rsamtools, dichromat, rtracklayer, scales
// Downstream: CAFE
//
// Install: BiocManager::install("biovizBase")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOVIZBASE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biovizbase"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biovizbase:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biovizbase:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biovizbase_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biovizbase_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biovizbase_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GCcontent)
    library(GRanges)
    library(IRanges)
    library(jsonlite)

    # --- Colorblindpal [] ---
    # Key functions: colorBlindSafePal, mypalFun
    ## with no arguments, return blind.pal.info
    head(colorBlindSafePal())
    ##
    mypalFun <- colorBlindSafePal("Set2")
    ## mypalFun(12, repeatable = FALSE) #only three
    # --- Color Dichromat [] ---
    # Key functions: colorBlindSafePal, showColor, mypalFun, dichromat
    ## for palette "Paried"
    mypalFun <- colorBlindSafePal(21)
    par(mfrow = c(1, 3))
    showColor(mypalFun(4))
    library(dichromat)
    # --- Cytoband Color [] ---
    # Key functions: getOption, getBioColor, option
    getOption("biovizBase")$cytobandColor
    getBioColor("CYTOBAND")
    ## differece source from default or options.
    opts <- getOption("biovizBase")
    opts$DNABasesNColor[1] <- "red"
    # --- Cytoband Color Legend [] ---
    # Key functions: getBioColor, plotColorLegend
    cols <- getBioColor("CYTOBAND")
    plotColorLegend(cols, title  = "cytoband")
    # --- Strand Color [] ---
    # Key functions: getBioColor, showColor, dichromat
    par(mfrow = c(1, 3))
    cols <- getBioColor("STRAND")
    showColor(cols)
    showColor(dichromat(cols, "deutan"))
    showColor(dichromat(cols, "protan"))
    # --- Base Color [] ---
    # Key functions: getBioColor
    getBioColor("DNA_BASES_N")
    # --- Ne Dichromat [] ---
    # Key functions: getBioColor, showColor, dichromat
    par(mfrow = c(1, 3))
    cols <- getBioColor("DNA_BASES_N", "default")
    showColor(cols, "name")
    cols.deu <- dichromat(cols, "deutan")
    names(cols.deu) <- names(cols)
    # --- Sample Gr [] ---
    # Key functions: GRanges, sample, IRanges, rnorm
    library(GenomicRanges)
    set.seed(1)
    N <- 500
    # --- Addstepping Gr [] ---
    # Key functions: addStepping, GRanges, IRanges
    head(addStepping(gr))
    head(addStepping(gr, group.name = "pair"))
    gr.close <- GRanges(c("chr1", "chr1"), IRanges(c(10, 20), width = 9))
    addStepping(gr.close)
    addStepping(gr.close, extend.size = 5)
    # --- Maxgap [] ---
    # Key functions: GRanges, IRanges, maxGap, gaps, start
    gr.temp <- GRanges("chr1", IRanges(start = c(100, 250),
                                     end = c(200, 300)))
    maxGap(gaps(gr.temp, start = min(start(gr.temp))))
    maxGap(gaps(gr.temp, start = min(start(gr.temp))), ratio = 0.5)
    # --- Shrink Single [] ---
    # Key functions: GRanges, IRanges, shrinkageFun, gaps, maxGap, fun1
    gr1 <- GRanges("chr1", IRanges(start = c(100, 300, 600),
                                   end = c(200, 400, 800)))
    shrink.fun1 <- shrinkageFun(gaps(gr1), max.gap = maxGap(gaps(gr1), 0.15))
    shrink.fun2 <- shrinkageFun(gaps(gr1), max.gap = 0)
    head(shrink.fun1(gr1))
    # --- Shrinkagefun [] ---
    # Key functions: GRanges, IRanges, intersect, gaps, start, shrinkageFun
    gr2 <- GRanges("chr1", IRanges(start = c(100, 350, 550),
                                   end = c(220, 500, 900)))
    gaps.gr <- intersect(gaps(gr1, start = min(start(gr1))),
                         gaps(gr2, start = min(start(gr2))))
    shrink.fun <- shrinkageFun(gaps.gr, max.gap = maxGap(gaps.gr))
    # --- Gc Content [] ---
    # Key functions: GCcontent, GRanges, IRanges
    ## library(BSgenome.Hsapiens.UCSC.hg19)
    ## GCcontent(Hsapiens, GRanges("chr1", IRanges(1e6, 1e6 + 1000)))
    ## GCcontent(Hsapiens, GRanges("chr1", IRanges(1e6, 1e6 + 1000)), view.width = 300)
    # --- Pileupasgranges [] ---
    # Key functions: pileupAsGRanges, pileupGRangesAsVariantTable
    ## library(Rsamtools)
    ## data(genesymbol)
    ## library(BSgenome.Hsapiens.UCSC.hg19)
    ## bamfile <- system.file("extdata", "SRR027894subRBM17.bam", package="biovizBase")
    ## test <- pileupAsGRanges(bamfile, region = genesymbol["RBM17"])
    # --- Ucsc Genome [] ---
    # Key functions: getIdeogram
    ## library(rtracklayer)
    ## hg19IdeogramCyto <- getIdeogram("hg19", cytoband = TRUE)
    ## hg19Ideogram <- getIdeogram("hg19", cytoband = FALSE)
    ## unknowIdeogram <- getIdeogram()

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biovizbase_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biovizbase_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biovizbase_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOVIZBASE:", paste0("    biovizbase: ", packageVersion("biovizBase"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biovizbase_results.csv
    touch ${prefix}_biovizbase_output.rds
    echo "BIOC_BIOVIZBASE:" > versions.yml
    echo "    biovizbase: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOVIZBASE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOVIZBASE(ch_input)

    emit:
    results  = BIOC_BIOVIZBASE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOVIZBASE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOVIZBASE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOVIZBASE.out.versions  // channel: path(versions.yml)
}
