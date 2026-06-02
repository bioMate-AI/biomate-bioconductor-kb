#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gmapR
// GSNAP and GMAP are a pair of tools to align short-read data written by Tom Wu.  This package provide
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gmapR/inst/doc/gmapR.R
// Upstream  : LungCancerLines
// Downstream: none
//
// Install: BiocManager::install("gmapR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GMAPR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gmapr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gmapr:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gmapr:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gmapr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gmapr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gmapr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(BamTallyParam)
    library(GmapGenome)
    library(GsnapParam)
    library(LungCancerFastqFiles)
    library(TP53Genome)
    library(jsonlite)

    # --- Create Gmapgenome [] ---
    # Key functions: requireNamespace, packages, path
    ## library(gmapR)
    ##
    # --- Get Tp53 Coordinates [] ---
    # Key functions: transcripts, strand
    library("org.Hs.eg.db")
    library("TxDb.Hsapiens.UCSC.hg19.knownGene")
    eg <- org.Hs.eg.db::org.Hs.egSYMBOL2EG[["TP53"]]
    txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
    tx <- transcripts(txdb, filter = list(gene_id = eg))
    # --- Get Tp53 Seq [] ---
    # Key functions: getSeq, GmapGenome
    library("BSgenome.Hsapiens.UCSC.hg19")
    library("gmapR")
    p53Seq <- getSeq(BSgenome.Hsapiens.UCSC.hg19::Hsapiens, roi,
                     as.character = FALSE)
    names(p53Seq) <- "TP53"
    # --- Set Tp53 Splicesites [] ---
    # Key functions: subsetRegion, exonsBy, spliceSites
    exons <- gmapR:::subsetRegion(exonsBy(txdb), roi, "TP53")
    spliceSites(gmapGenome, "knownGene") <- exons
    # --- Get Lung Cancer Fastqs [] ---
    # Key functions: LungCancerFastqFiles
    library("LungCancerLines")
    fastqs <- LungCancerFastqFiles()
    # --- Create Gsnapparam [] ---
    # Key functions: GsnapParam
    ##specify how GSNAP should behave using a GsnapParam object
    # --- Align With Gsnap [] ---
    # Key functions: gsnap, dm3
    ## gsnapOutput <- gsnap(input_a=fastqs["H1993.first"],
    ##                      input_b=fastqs["H1993.last"],
    ##                      params=gsnapParam)
    ##
    ## ##gsnapOutput
    # --- Get Gsnap Bam Files [] ---
    # Key functions: path
    ## ##> dir(path(gsnapOutput), full.names=TRUE, pattern="\\.bam$")
    ## ##[1] "/local/Rtmporwsvr/file1cbc73503e9.1.nomapping.bam"
    ## ##[2] "/local/Rtmporwsvr/file1cbc73503e9.1.unpaired_mult.bam"
    ## ##[3] "/local/Rtmporwsvr/file1cbc73503e9.1.unpaired_transloc.bam"
    ## ##[4] "/local/Rtmporwsvr/file1cbc73503e9.1.unpaired_uniq.bam"
    # --- Tp53Genome Accessor [] ---
    # Key functions: TP53Genome
    genome <- TP53Genome()
    # --- Run Bamtally [] ---
    # Key functions: BamTallyParam, bam_tally, variantSummary
    ## bam_file <- system.file("extdata/H1993.analyzed.bam",
    ##                         package="LungCancerLines", mustWork=TRUE)
    ## breaks <- c(0L, 15L, 60L, 75L)
    ## bqual <- 56L
    ## mapq <- 13L
    # --- Create Gmapgenomepackge [] ---
    # Key functions: makeGmapGenomePackage

    # --- Create Hg19 Gmapgenome [] ---
    # Key functions: requireNamespace, packages, GmapGenome


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gmapr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gmapr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gmapr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GMAPR:", paste0("    gmapr: ", packageVersion("gmapR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gmapr_results.csv
    touch ${prefix}_gmapr_output.rds
    echo "BIOC_GMAPR:" > versions.yml
    echo "    gmapr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GMAPR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GMAPR(ch_input)

    emit:
    results  = BIOC_GMAPR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GMAPR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GMAPR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GMAPR.out.versions  // channel: path(versions.yml)
}
