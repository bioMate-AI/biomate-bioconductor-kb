#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: biomvRCNS
// In this package, a Hidden Semi Markov Model (HSMM) and one homogeneous segmentation model are design
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/biomvRCNS/inst/doc/biomvRCNS.R
// Upstream  : Rsamtools
// Downstream: none
//
// Install: BiocManager::install("biomvRCNS")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BIOMVRCNS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-biomvrcns"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-biomvrcns:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-biomvrcns:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_biomvrcns_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_biomvrcns_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_biomvrcns_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DataFrame)
    library(GRanges)
    library(IRanges)
    library(ScanBamParam)
    library(jsonlite)

    # --- Coriellgr [] ---
    # Key functions: GRanges, IRanges, values, DataFrame
    data('coriell', package='biomvRCNS')
    head(coriell, n=3)
    xgr<-GRanges(seqnames=coriell[,2],
    	IRanges(start=coriell[,3], width=1, names=coriell[,1]))
    values(xgr)<-DataFrame(coriell[,4:5], row.names=NULL)
    # --- Coriellhsmm [] ---
    # Key functions: biomvRhsmm
    rhsmm<-biomvRhsmm(x=xgr, maxbp=1E5, J=3, soj.type='gamma',
    	com.emis=T, emis.type='norm', prior.m='quantile', grp=c(1,2))
    # --- Coriellhsmmplot [] ---
    # Key functions: biomvRGviz, seqnames, mcols
    obj<-biomvRGviz(exprgr=xgr[seqnames(xgr)=='11', 'Coriell.05296'],
    	seggr=rhsmm@res[mcols(rhsmm@res)[,'SAMPLE']=='Coriell.05296'], tofile=FALSE)
    # --- Coriellseg [] ---
    # Key functions: biomvRseg
    rseg<-biomvRseg(x=xgr, maxbp=4E4, maxseg=10, family='norm', grp=c(1,2))
    # --- Coriellmgmr [] ---
    # Key functions: biomvRmgmr
    rmgmrh<-biomvRmgmr(xgr, q=0.9, high=T, maxgap=1000, minrun=2500, grp=c(1,2))
    rmgmrl<-biomvRmgmr(xgr, q=0.1, high=F, maxgap=1000, minrun=2500, grp=c(1,2))
    res<-c(rmgmrh@res, rmgmrl@res)
    # --- Buildencodecgr [] ---
    # Key functions: GRanges, IRanges, ScanBamParam, scanBamWhat
    ## winsize<-25
    ## cgr<-GRanges("chr17", strand='-',
    ## 	IRanges(start=seq(7560001, 7610000, winsize), width =winsize))
    ## bf<-system.file("extdata", "encodeFiles.txt", package = "biomvRCNS")
    ## bamfiles<-read.table(bf, header=T, stringsAsFactors=F)
    # --- Create GenomicRanges object [] ---
    # Key functions: GRanges, IRanges, ScanBamParam, scanBamFlag
    ## cgr<-GRanges("chr17", strand='-',
    ## 	IRanges(seq(7560001, 7610000), width=1))
    ## bf<-system.file("extdata", "encodeFiles.txt", package = "biomvRCNS")
    ## bamfiles<-read.table(bf, header=T, stringsAsFactors=F)
    ## library(Rsamtools)
    # --- Buildencodegmgr [] ---
    # Key functions: GRanges, IRanges
    ## af<-system.file("extdata", "gmodTP53.gff", package = "biomvRCNS")
    ## gtfsub<-read.table(af, fill=T, stringsAsFactors=F)
    ## gmgr<-GRanges("chr17", IRanges(start=gtfsub[, 4], end=gtfsub[, 5],
    ## 	names=gtfsub[, 13]), strand=gtfsub[, 7], TYPE=gtfsub[, 3])
    # --- Poolencodecgr [] ---
    # Key functions: mcols, DataFrame, rowSums
    data(encodeTP53)
    cgr<-encodeTP53$cgr
    gmgr<-encodeTP53$gmgr
    mcols(cgr)<-DataFrame(
    	Gm12878=1+rowSums(as.matrix(mcols(cgr)[,1:2])),
    # --- Encodehsmmtxdbsojourn [] ---
    # Key functions: biomvRhsmm
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    txdb<-TxDb.Hsapiens.UCSC.hg19.knownGene
    rhsmm<-biomvRhsmm(x=cgr, xAnno=txdb, maxbp=1E3, soj.type='gamma',
    	emis.type='pois', prior.m='quantile', q.alpha=0.01)
    # --- Showencodehsmm [] ---
    # Key functions: mcols
    rhsmm@res[mcols(rhsmm@res)[,'STATE']=='exon']
    # --- Plotencodehsmmg [] ---
    # Key functions: mcols, biomvRGviz
    g<-mcols(rhsmm@res)[,'STATE']=='exon' & mcols(rhsmm@res)[,'SAMPLE']=='Gm12878'
    obj<-biomvRGviz(exprgr=cgr[,'Gm12878'], gmgr=gmgr,
    	seggr=rhsmm@res[g], plotstrand='-', regionID='TP53', tofile=FALSE)
    # --- Plotencodehsmmk [] ---
    # Key functions: mcols, biomvRGviz
    k<-mcols(rhsmm@res)[,'STATE']=='exon' & mcols(rhsmm@res)[,'SAMPLE']=='K562'
    obj<-biomvRGviz(exprgr=cgr[,'K562'], gmgr=gmgr,
      seggr=rhsmm@res[k], plotstrand='-', regionID='TP53', tofile=FALSE)
    # --- Findnew [] ---
    # Key functions: queryHits, findOverlaps, setdiff
    nK2gm<-queryHits(findOverlaps(rhsmm@res[k], gmgr))
    nK2G<-queryHits(findOverlaps(rhsmm@res[k], rhsmm@res[g]))
    rhsmm@res[k][setdiff(seq_len(sum(k)), unique(c(nK2G, nK2gm)))]
    # --- Encodeothers [] ---
    # Key functions: biomvRseg, biomvRmgmr
    rseg<-biomvRseg(x=cgr, maxbp=1E3, maxseg=20, family='pois')
    rmgmr<-biomvRmgmr(x=cgr, q=0.99, maxgap=50, minrun=100)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_biomvrcns_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_biomvrcns_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_biomvrcns_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_BIOMVRCNS:", paste0("    biomvrcns: ", packageVersion("biomvRCNS"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_biomvrcns_results.csv
    touch ${prefix}_biomvrcns_output.rds
    echo "BIOC_BIOMVRCNS:" > versions.yml
    echo "    biomvrcns: 0.0.0" >> versions.yml
    """
}


workflow BIOC_BIOMVRCNS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_BIOMVRCNS(ch_input)

    emit:
    results  = BIOC_BIOMVRCNS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_BIOMVRCNS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_BIOMVRCNS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_BIOMVRCNS.out.versions  // channel: path(versions.yml)
}
