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
    library(customProDB)
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

    # --- Variant Processing and Annotation [] ---
    # Key functions: InputVcf, Varlocation, Positionincoding
    vcf_file <- system.file("extdata/vcfs", "test1.vcf", package="customProDB")
    vcf <- InputVcf(vcf_file)
    is_indel <- values(vcf[[1]])[['INDEL']]
    snv_vcf <- vcf[[1]][which(!is_indel)]
    txdb_file <- system.file("extdata/refseq", "txdb.sqlite", package="customProDB")
    txdb <- AnnotationDbi::loadDb(txdb_file)
    ids_file <- system.file("extdata/refseq", "ids.RData", package="customProDB")
    load(ids_file)
    snv_loc <- Varlocation(snv_vcf, txdb, ids)
    exon_file <- system.file("extdata/refseq", "exon_anno.RData", package="customProDB")
    load(exon_file)
    dbsnp_file <- system.file("extdata/refseq", "dbsnpinCoding.RData", package="customProDB")
    load(dbsnp_file)
    cosmic_file <- system.file("extdata/refseq", "cosmic.RData", package="customProDB")
    load(cosmic_file)
    postable_snv <- Positionincoding(snv_vcf, exon, dbsnpinCoding, COSMIC=cosmic)


    # --- Translation of Variants to Protein Sequences [] ---
    # Key functions: aaVariation, OutputVarproseq, Outputaberrant
    procoding_file <- system.file("extdata/refseq", "procodingseq.RData", package="customProDB")
    load(procoding_file)
    txlist <- unique(postable_snv[, "txid"])
    codingseq <- procodingseq[procodingseq[, "tx_id"] %in% txlist, ]
    mtab <- aaVariation(postable_snv, codingseq)
    pro_file <- system.file("extdata/refseq", "proseq.RData", package="customProDB")
    load(pro_file)
    ids_file <- system.file("extdata/refseq", "ids.RData", package="customProDB")
    load(ids_file)
    out_snv <- tempfile(fileext=".fasta")
    OutputVarproseq(mtab, proteinseq, out_snv, ids)


    # --- Junction Analysis and Novel Junction Translation [] ---
    # Key functions: Bed2Range, JunctionType, OutputNovelJun
    bed_file <- system.file("extdata/beds", "junctions1.bed", package="customProDB")
    jun <- Bed2Range(bed_file, skip=1, covfilter=5)
    splicemax_file <- system.file("extdata/refseq", "splicemax.RData", package="customProDB")
    load(splicemax_file)
    ids_file <- system.file("extdata/refseq", "ids.RData", package="customProDB")
    load(ids_file)
    txdb_file <- system.file("extdata/refseq", "txdb.sqlite", package="customProDB")
    txdb <- AnnotationDbi::loadDb(txdb_file)
    junction_type <- JunctionType(jun, splicemax, txdb, ids)
    pro_file <- system.file("extdata/refseq", "proseq.RData", package="customProDB")
    load(pro_file)
    out_junc <- tempfile(fileext=".fasta")
    hg19 <- BSgenome::getBSgenome("BSgenome.Hsapiens.UCSC.hg19")
    OutputNovelJun(junction_type, hg19, out_junc, proteinseq)


    # --- Integrated Pipeline Execution [] ---
    # Key functions: easyRun
    bam_file <- system.file("extdata/bams", "test1_sort.bam", package="customProDB")
    vcf_file <- system.file("extdata/vcfs", "test1.vcf", package="customProDB")
    bed_file <- system.file("extdata", "junctions.bed", package="customProDB")
    anno_path <- system.file("extdata/refseq", package="customProDB")
    out_dir <- tempdir()
    easyRun(
        bamFile=bam_file, RPKM=NULL, vcffile=vcf_file,
        annotation_path=anno_path, outfile_path=out_dir,
        outfile_name="test_run", rpkm_cutoff=1, INDEL=TRUE,
        lablersid=TRUE, COSMIC=TRUE, nov_junction=FALSE
    )

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
