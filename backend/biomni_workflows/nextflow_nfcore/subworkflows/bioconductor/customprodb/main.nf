#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: customProDB
// Database search is the most widely used approach for peptide and protein identification in mass spec
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/customProDB/inst/doc/customProDB.R
// Upstream  : rtracklayer
// Downstream: none
//
// Install: BiocManager::install("customProDB")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CUSTOMPRODB {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-customprodb"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-customprodb:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-customprodb:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_customprodb_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_customprodb_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_customprodb_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Bed2Range)
    library(InputVcf)
    library(JunctionType)
    library(Multiple_VCF)
    library(OutputNovelJun)
    library(OutputVarproseq)
    library(Outputaberrant)
    library(Outputproseq)
    library(Positionincoding)
    library(PrepareAnnotationEnsembl)
    library(jsonlite)

    # --- Dbsnpversion [] ---
    # Key functions: browserSession, genome, trackNames
    ## library('rtracklayer')
    ## session <- browserSession()
    ## genome(session) <- 'hg19'
    ## dbsnps <- trackNames(session)[grep('snp', trackNames(session), fixed=T)]
    ## dbsnps
    # --- Prepareannoref [] ---
    # Key functions: tempdir, PrepareAnnotationRefseq
    ## transcript_ids <- c("NM_001126112", "NM_033360", "NR_073499", "NM_004448",
    ## 			"NM_000179", "NR_029605", "NM_004333", "NM_001127511")
    ## pepfasta <- system.file("extdata", "refseq_pro_seq.fasta",
    ## 				package="customProDB")
    # --- Prepareannoensembl [] ---
    # Key functions: useMart, tempdir, PrepareAnnotationEnsembl
    ## ensembl <- useMart("ENSEMBL_MART_ENSEMBL", dataset="hsapiens_gene_ensembl",
    ##     host="may2015.archive.ensembl.org", path="/biomart/martservice",
    ##     archive=FALSE)
    ## annotation_path <- tempdir()
    # --- Calculate [] ---
    # Key functions: calculateRPKM
    load(system.file("extdata/refseq", "exon_anno.RData", package="customProDB"))
    bamFile <- system.file("extdata/bams", "test1_sort.bam", package="customProDB")
    load(system.file("extdata/refseq", "ids.RData", package="customProDB"))
    RPKM <- calculateRPKM(bamFile, exon, proteincodingonly=TRUE, ids)
    # --- Ouputpro [] ---
    # Key functions: tempdir, Outputproseq
    load(system.file("extdata/refseq", "proseq.RData", package="customProDB"))
    outf1 <- paste(tempdir(), '/test_rpkm.fasta', sep='')
    Outputproseq(RPKM, 1, proteinseq, outf1, ids)
    # --- Inpvcf [] ---
    # Key functions: InputVcf
    # single sample
    vcffile <- system.file("extdata/vcfs", "test1.vcf", package="customProDB")
    vcf <- InputVcf(vcffile)
    length(vcf)
    vcf[[1]][1:3]
    # --- Inpvcfm [] ---
    # Key functions: InputVcf
    # multiple samples in one VCF file
    vcffile <- system.file("extdata", "test_mul.vcf", package="customProDB")
    vcfs <- InputVcf(vcffile)
    # --- Location [] ---
    # Key functions: values, loadDb, Varlocation
    table(values(vcf[[1]])[['INDEL']])
    index <- which(values(vcf[[1]])[['INDEL']]==TRUE)
    indelvcf <- vcf[[1]][index]
    index <- which(values(vcf[[1]])[['INDEL']]==FALSE)
    SNVvcf <- vcf[[1]][index]
    # --- Poscoding [] ---
    # Key functions: Positionincoding
    load(system.file("extdata/refseq", "exon_anno.RData", package="customProDB"))
    load(system.file("extdata/refseq", "dbsnpinCoding.RData", package="customProDB"))
    load(system.file("extdata/refseq", "cosmic.RData", package="customProDB"))
    postable_snv <- Positionincoding(SNVvcf, exon, dbsnpinCoding, COSMIC=cosmic)
    postable_snv
    # --- Aavar [] ---
    # Key functions: aaVariation
    load(system.file("extdata/refseq", "procodingseq.RData", package="customProDB"))
    txlist <- unique(postable_snv[, 'txid'])
    codingseq <- procodingseq[procodingseq[, 'tx_id'] %in% txlist,]
    mtab <- aaVariation (postable_snv, codingseq)
    mtab
    # --- Outvarpro [] ---
    # Key functions: tempdir, OutputVarproseq
    outfile <-  paste(tempdir(), '/test_snv.fasta', sep='')
    load(system.file("extdata/refseq", "proseq.RData", package="customProDB"))
    OutputVarproseq(mtab, proteinseq, outfile, ids)
    # --- Outabber [] ---
    # Key functions: tempdir, Outputaberrant
    txlist_indel <- unique(postable_indel[, 'txid'])
    codingseq_indel <- procodingseq[procodingseq[, 'tx_id'] %in% txlist_indel, ]
    outfile <-  paste(tempdir(), '/test_indel.fasta', sep='')
    Outputaberrant(postable_indel, coding=codingseq_indel, proteinseq=proteinseq,
    			outfile=outfile, ids=ids)
    # --- Junctype [] ---
    # Key functions: Bed2Range, JunctionType
    bedfile <- system.file("extdata/beds", "junctions1.bed", package="customProDB")
    jun <-  Bed2Range(bedfile,skip=1,covfilter=5)
    jun
    load(system.file("extdata/refseq", "splicemax.RData", package="customProDB"))
    load(system.file("extdata/refseq", "ids.RData", package="customProDB"))
    # --- Novjunc [] ---
    # Key functions: tempdir, OutputNovelJun
    outf_junc <- paste(tempdir(), '/test_junc.fasta',sep='')
    library('BSgenome.Hsapiens.UCSC.hg19')
    OutputNovelJun <- OutputNovelJun(junction_type, Hsapiens, outf_junc,
            proteinseq)
    # --- Sharedpro [] ---
    # Key functions: files, calculateRPKM
    path <- system.file("extdata/bams", package="customProDB")
    bamFile<- paste(path, '/', list.files(path,pattern="*bam$"), sep='')
    rpkms <- sapply(bamFile, function(x)
    			calculateRPKM(x, exon, proteincodingonly=TRUE, ids))
    #colnames(rpkms) <- c('1', '2', '3')

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_customprodb_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_customprodb_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_customprodb_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CUSTOMPRODB:", paste0("    customprodb: ", packageVersion("customProDB"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_customprodb_results.csv
    touch ${prefix}_customprodb_output.rds
    echo "BIOC_CUSTOMPRODB:" > versions.yml
    echo "    customprodb: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CUSTOMPRODB_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CUSTOMPRODB(ch_input)

    emit:
    results  = BIOC_CUSTOMPRODB.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CUSTOMPRODB.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CUSTOMPRODB.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CUSTOMPRODB.out.versions  // channel: path(versions.yml)
}
