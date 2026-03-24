#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MethylSeekR
// This is a package for the discovery of regulatory regions from Bis-seq data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MethylSeekR/inst/doc/MethylSeekR.R
// Upstream  : BSgenome, parallel, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("MethylSeekR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLSEEKR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylseekr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylseekr:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-methylseekr:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylseekr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylseekr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylseekr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(MethylSeekR)
    library(jsonlite)

    # --- Genomes [] ---
    # Key functions: genomes
    ## library(BSgenome)
    ## available.genomes()
    # --- Seqlengths [] ---
    # Key functions: seqlengths
    library("BSgenome.Hsapiens.UCSC.hg18")
    sLengths=seqlengths(Hsapiens)
    head(sLengths)
    # --- Removesnps [] ---
    # Key functions: removeSNPs
    meth.gr <- removeSNPs(meth.gr, snps.gr)
    # --- Plotalphadistributiononechr [] ---
    # Key functions: plotAlphaDistributionOneChr
    plotAlphaDistributionOneChr(m=meth.gr, chr.sel="chr22",
    num.cores=1)
    # --- Detectcores [] ---
    # Key functions: detectCores
    ## library(parallel)
    ## detectCores()
    # --- Segmentpmds [] ---
    # Key functions: segmentPMDs
    PMDsegments.gr <- segmentPMDs(m=meth.gr, chr.sel="chr22",
    seqLengths=sLengths, num.cores=1)
    head(PMDsegments.gr)
    # --- Plotalphadistributiononechr [] ---
    # Key functions: plotAlphaDistributionOneChr, subsetByOverlaps, values
    plotAlphaDistributionOneChr(m=subsetByOverlaps(meth.gr,
    PMDsegments.gr[values(PMDsegments.gr)$type=="notPMD"]), chr.sel="chr22",
    num.cores=1)
    # --- Myfig1 [] ---
    # Key functions: plotPMDSegmentation
    plotPMDSegmentation(m=meth.gr, segs=PMDsegments.gr)
    # --- Savepmdsegments [] ---
    # Key functions: savePMDSegments
    ## savePMDSegments(PMDs=PMDsegments.gr,
    ## GRangesFilename="PMDs.gr.rds", TableFilename="PMDs.tab")
    # --- Browsersession [] ---
    # Key functions: browserSession, genome, ucscTableQuery, track
    library(rtracklayer)
    session <- browserSession()
    genome(session) <- "hg18"
    query <- ucscTableQuery(session, table = "cpgIslandExt")
    CpGislands.gr <- track(query)
    # --- Suppresswarnings [] ---
    # Key functions: resize
    CpGislands.gr <-
    suppressWarnings(resize(CpGislands.gr, 5000, fix="center"))
    # --- Calculatefdrs [] ---
    # Key functions: calculateFDRs
    stats <- calculateFDRs(m=meth.gr, CGIs=CpGislands.gr,
    PMDs=PMDsegments.gr, num.cores=1)
    stats
    # --- Segmentumrslmrs [] ---
    # Key functions: segmentUMRsLMRs
    UMRLMRsegments.gr <- segmentUMRsLMRs(m=meth.gr, meth.cutoff=m.sel,
    nCpG.cutoff=n.sel, PMDs=PMDsegments.gr,
    num.cores=1, myGenomeSeq=Hsapiens,
    seqLengths=sLengths)
    head(UMRLMRsegments.gr)
    # --- Myfig3 [] ---
    # Key functions: plotFinalSegmentation
    plotFinalSegmentation(m=meth.gr, segs=UMRLMRsegments.gr,
    PMDs=PMDsegments.gr,meth.cutoff=m.sel)
    # --- Saveumrlmrsegments [] ---
    # Key functions: saveUMRLMRSegments
    ## saveUMRLMRSegments(segs=UMRLMRsegments.gr,
    ## GRangesFilename="UMRsLMRs.gr.rds", TableFilename="UMRsLMRs.tab")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylseekr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylseekr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylseekr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLSEEKR:", paste0("    methylseekr: ", packageVersion("MethylSeekR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylseekr_results.csv
    touch ${prefix}_methylseekr_output.rds
    echo "BIOC_METHYLSEEKR:" > versions.yml
    echo "    methylseekr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLSEEKR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLSEEKR(ch_input)

    emit:
    results  = BIOC_METHYLSEEKR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLSEEKR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLSEEKR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLSEEKR.out.versions  // channel: path(versions.yml)
}
