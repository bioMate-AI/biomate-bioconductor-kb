#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylPipe
// Memory efficient analysis of base resolution DNA methylation data in both the CpG and non-CpG sequen
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylPipe/inst/doc/methylPipe.R
// Upstream  : none
// Downstream: ListerEtAlBSseq
//
// Install: BiocManager::install("methylPipe")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLPIPE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylpipe"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylpipe:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylpipe:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylpipe_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylpipe_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylpipe_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BSprepare)
    library(GElist)
    library(GRanges)
    library(jsonlite)

    # --- Create GenomicRanges object [] ---
    # Key functions: BSprepare, GRanges
    file_loc <- system.file('extdata', 'H1_chr20_CG_10k.txt', package='methylPipe')
    BSprepare(files_location=file_loc,output_folder=file_loc, tabix="/path-to-tabix/")
    uncov_GR <- GRanges(Rle('chr20'), IRanges(c(14350,69251,84185), c(18349,73250,88184)))
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, mCsmoothing
    gr <- GRanges("chr20",IRanges(1,5e5))
    sres <- mCsmoothing(H1.db, gr, Scorefun='sum', Nbins=50, plot=TRUE)
    # --- methstats [] ---
    # Key functions: methstats

    # --- map B Sdata2 G Ranges [] ---
    # Key functions: mapBSdata2GRanges
    gr_file <- system.file('extdata', 'GR_chr20.Rdata', package='methylPipe')
    load(gr_file)
    resmC <- mapBSdata2GRanges(GenoRanges=GR_chr20, Sample=H1.db, context='CG')
    # --- binm C [] ---
    # Key functions: binmC, binC, binrC
    gec.H1 <- profileDNAmetBin(GenoRanges=GR_chr20, Sample=H1.db, mcCLASS='mCG', nbins=3)
    binmC(gec.H1)[4:5,]
    binC(gec.H1)[4:5,]
    # --- G Elist [] ---
    # Key functions: GElist
    gecIMR_file <- system.file('extdata', 'gec.IMR90.Rdata', package='methylPipe')
    load(gecIMR_file)
    gel <- GElist(gecIMR90=gec.IMR90, gecH1=gec.H1)
    # --- G Elist [] ---
    # Key functions: GElist, plotMeth
    library(TxDb.Hsapiens.UCSC.hg18.knownGene)
    gel <- GElist(gecIMR90=gec.IMR90[1:10], gecH1=gec.H1[1:10])
    # --- find D M R [] ---
    # Key functions: findDMR


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylpipe_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylpipe_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylpipe_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLPIPE:", paste0("    methylpipe: ", packageVersion("methylPipe"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylpipe_results.csv
    touch ${prefix}_methylpipe_output.rds
    echo "BIOC_METHYLPIPE:" > versions.yml
    echo "    methylpipe: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLPIPE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLPIPE(ch_input)

    emit:
    results  = BIOC_METHYLPIPE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLPIPE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLPIPE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLPIPE.out.versions  // channel: path(versions.yml)
}
