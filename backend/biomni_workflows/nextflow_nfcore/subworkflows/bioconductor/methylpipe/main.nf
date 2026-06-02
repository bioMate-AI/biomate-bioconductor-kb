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
    library(methylPipe)
    library(BSprepare)
    library(GElist)
    library(GRanges)
    library(jsonlite)

    # --- Methylation Calling and Database Creation ---
    # Key functions: meth.call, BSdata, BSdataSet
    file_loc <- system.file('extdata', 'test_methcall', package='methylPipe')
    meth.call(files_location=file_loc, output_folder=tempdir(),
              no_overlap=TRUE, read.context="CpG", Nproc=1)
    uncov_GR <- GenomicRanges::GRanges(
        GenomicRanges::Rle('chr20'),
        IRanges::IRanges(c(14350, 69251, 84185), c(18349, 73250, 88184))
    )
    H1data <- system.file('extdata', 'H1_chr20_CG_10k_tabix_out.txt.gz',
                          package='methylPipe')
    Hsapiens <- BSgenome.Hsapiens.UCSC.hg18::Hsapiens
    H1.db <- BSdata(file=H1data, uncov=uncov_GR, org=Hsapiens)
    IMR90data <- system.file('extdata', 'IMR90_chr20_CG_10k_tabix_out.txt.gz',
                             package='methylPipe')
    IMR90.db <- BSdata(file=IMR90data, uncov=uncov_GR, org=Hsapiens)
    H1.IMR90.set <- BSdataSet(org=Hsapiens, group=c("C","E"),
                              IMR90=IMR90.db, H1=H1.db)

    # --- Methylation Profiling and Smoothing ---
    # Key functions: mCsmoothing, mapBSdata2GRanges, profileDNAmetBin
    gr <- GenomicRanges::GRanges("chr20", IRanges::IRanges(1, 5e5))
    sres <- mCsmoothing(H1.db, gr, Scorefun='sum', Nbins=50, plot=FALSE)
    gr_file <- system.file('extdata', 'GR_chr20.Rdata', package='methylPipe')
    load(gr_file)
    resmC <- mapBSdata2GRanges(GenoRanges=GR_chr20, Sample=H1.db,
                               context='CG')
    gec.H1 <- profileDNAmetBin(GenoRanges=GR_chr20, Sample=H1.db,
                               mcCLASS='mCG', nbins=3)

    # --- Differential Methylation Analysis ---
    # Key functions: methstats, findDMR, consolidateDMRs
    gr_file <- system.file('extdata', 'GR_chr20.Rdata', package='methylPipe')
    load(gr_file)
    stats.set <- BSdataSet(org=Hsapiens, group=c("C","C","E","E"),
                           IMR_1=IMR90.db, IMR_2=IMR90.db,
                           H1_1=H1.db, H1_2=H1.db)
    stats_res <- methstats(stats.set, chrom="chr20", mcClass='mCG',
                           Nproc=1)
    DMRs <- findDMR(object=H1.IMR90.set, Nproc=1, ROI=GR_chr20,
                    MCClass='mCG', dmrSize=6, dmrBp=800)
    hyper.DMRs.conso <- consolidateDMRs(DmrGR=DMRs, pvThr=0.05,
                                         GAP=100, type="hyper")

    # --- Visualization and Genomic Integration ---
    # Key functions: GElist, plotMeth
    gecIMR_file <- system.file('extdata', 'gec.IMR90.Rdata',
                               package='methylPipe')
    load(gecIMR_file)
    txdb <- TxDb.Hsapiens.UCSC.hg18.knownGene::TxDb.Hsapiens.UCSC.hg18.knownGene
    gel <- GElist(gecIMR90=gec.IMR90[1:10], gecH1=gec.H1[1:10])
    plotMeth(gel, colors=c("red","blue"), datatype=c("mC","mC"),
             yLim=c(.025, .025), brmeth=list(IMR90=IMR90.db, H1=H1.db),
             mcContext="CG", transcriptDB=txdb, chr="chr20",
             start=14350, end=277370, org=Hsapiens)


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
