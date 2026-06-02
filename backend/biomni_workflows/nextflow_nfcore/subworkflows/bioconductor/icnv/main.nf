#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: iCNV
// Integrative copy number variation (CNV) detection from multiple platform and experimental design.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/iCNV/inst/doc/iCNV-vignette.R
// Upstream  : CODEX
// Downstream: none
//
// Install: BiocManager::install("iCNV")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ICNV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-icnv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-icnv:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-icnv:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_icnv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_icnv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_icnv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(iCNV)
    library(jsonlite)


    # --- Codex Normalization 1 [] ---
    # Key functions: list.files, read.table, getbambed, extdata, sampname, chr22_400_to_500.bed, icnv.demo.
    ### 2.2 code chunk number 1: bambedObj1
    library(CODEX)
    library(WES.1KG.WUGSC) # Load Toy data from the 1000 Genomes Project.
    library(iCNV) 
    # Assume your work dir set to demo
    dir <- system.file("extdata", package = "WES.1KG.WUGSC") # 'PATH/TO/BAM'
    bamFile <- list.files(dir, pattern = '*.bam$')
    bamdir <- file.path(dir, bamFile)
    sampname <- as.matrix(read.table(file.path(dir, "sampname")))
    bedFile <- file.path(dir, "chr22_400_to_500.bed")
    chr <- 22
    bambedObj <- getbambed(bamdir = bamdir, bedFile = bedFile, 
                       sampname = sampname, projectname = "icnv.demo.", chr)
    bamdir <- bambedObj$bamdir; sampname <- bambedObj$sampname
    ref <- bambedObj$ref; projectname <- bambedObj$projectname; chr <- bambedObj$chr

    # --- Codex Normalization 2 [] ---
    # Key functions: load, which.max, null, pmax, function, start, end, save
    load(paste0(projectname,'plrObj_',chr,".rda"))
    optK <- K[which.max(BIC)] # by default or customize given curves

    ### 2.2 code chunk number 6: plr
    Y_qc <- qcObj$Y_qc; sampname_qc <- qcObj$sampname_qc; gc_qc <- qcObj$gc_qc
    mapp_qc <- qcObj$mapp_qc; ref_qc <- qcObj$ref_qc; qcmat <- qcObj$qcmat
    Yhat <- normObj$Yhat; AIC <- normObj$AIC; BIC <- normObj$BIC
    RSS <- normObj$RSS; K <- normObj$K
    ref_qc <- qcObj$ref_qc # IRanges object for exon target
    sampname_qc <- qcObj$sampname_qc # sample names
    Y_norm <- normObj$Yhat[[optK]] # normalized read count under null (no CNV)
    plr <- log(pmax(Y_qc,0.0001)/pmax(Y_norm,0.0001)) # log transformed z-scores
    ngs_plr <- lapply(seq_len(ncol(plr)), function(i) plr[,i])
    ngs_plr.pos <- lapply(seq_len(ncol(plr)),function(x){return(cbind(start(ref_qc),end(ref_qc)))})
    save(sampname_qc,ngs_plr,ngs_plr.pos,file=paste0(projectname,'plrObj_',chr,'_',optK,'.rda'))

    # --- Results='hide' [] ---
    # Key functions: get_array_input, load, extdata, iCNV, icnv.demo.
    ### 2.4 code chunk number 1: icnv_array_input
    # PATH/TO/FOLDER where you stored the array data
    dir <- system.file("extdata", package="iCNV")#PATH/TO/FOLDER where you stored the array data
    chr <- 22
    projectname <- "icnv.demo."
    pattern <- paste0('*.csv.arrayicnv$')
    get_array_input(dir,pattern,chr,projectname)
    load(paste0(projectname,'array_lrrbaf_',chr,'.rda'))

    # --- Results='hide' [] ---
    # Key functions: str, iCNV_detection
    ### 2.5 code chunk number 1: iCNV_detection with genotype
    str(ngs_plr) # List of n vector, each one is the PLR for an exon
    str(ngs_plr.pos) # List of n matrix (p x 2), each one is the start and end location for an exon
    str(ngs_baf) # List of n vector, each one is the variants BAF from .bam
    str(ngs_baf.pos) # List of n vector, each one is the variants BAF position
    str(snp_lrr) # List of n vector, each one is the normalized LRR for a SNP
    str(snp_lrr.pos) # List of n vector, each one is a SNP position
    str(snp_baf) # List of n vector, each one is the BAF for a SNP
    str(snp_baf.pos) # List of n vector, each one is the SNP BAF position
    projectname <- 'icnv.demo.'
    icnv_res0 <- iCNV_detection(ngs_plr,snp_lrr,
                             ngs_baf,snp_baf,
                             ngs_plr.pos,snp_lrr.pos,
                             ngs_baf.pos,snp_baf.pos,
                             projname=projectname,CN=1,mu=c(-3,0,2),cap=TRUE,visual = 1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_icnv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_icnv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_icnv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ICNV:", paste0("    icnv: ", packageVersion("iCNV"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_icnv_results.csv
    touch ${prefix}_icnv_output.rds
    echo "BIOC_ICNV:" > versions.yml
    echo "    icnv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ICNV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ICNV(ch_input)

    emit:
    results  = BIOC_ICNV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ICNV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ICNV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ICNV.out.versions  // channel: path(versions.yml)
}
