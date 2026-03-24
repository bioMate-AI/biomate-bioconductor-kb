#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiTC
// The HiTC package was developed to explore high-throughput 'C' data such as 5C or Hi-C. Dedicated R c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiTC/inst/doc/HiC_analysis.R
// Upstream  : HiCDataHumanIMR90, Matrix, rtracklayer
// Downstream: none
//
// Install: BiocManager::install("HiTC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HITC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hitc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hitc:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hitc:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hitc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hitc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hitc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HTClist)
    library(jsonlite)

    # --- Head [] ---
    # Key functions: show, intdata, size
    require(HiTC)
    require(HiCDataHumanIMR90)
    data(Dixon2012_IMR90)
    show(hic_imr90_40)
    class(intdata(hic_imr90_40$chr1chr1))
    # --- Describe [] ---
    # Key functions: show, complete, isComplete, isPairwise, seqlevels, detail
    ## Show data
    show(hic_imr90_40)
    ## Is my data complete (i.e. composed of intra + the related inter chromosomal maps)
    isComplete(hic_imr90_40)
    ## Note that a complete object is not necessarily pairwise
    # --- Plot1 [] ---
    # Key functions: dataset, reduce, HTClist, mapC
    ## Go back to a smaller dataset (chr21, 22, X) at lower resolution
    sset <- reduce(hic_imr90_40, chr=c("chr5","chr6","chr7"))
    imr90_500 <- HTClist(lapply(sset, binningC,
                              binsize=500000, bin.adjust=FALSE, method="sum", step=1))
    mapC(imr90_500)
    # --- Plot2 [] ---
    # Key functions: mapC, forcePairwise
    mapC(forcePairwise(imr90_500), maxrange=200)
    # --- Resfrag [] ---
    # Key functions: getRestrictionFragmentsPerChromosome
    ## Example on chromosome X
    ## GRanges of restriction fragments after HindIII digestion
    resFrag <- getRestrictionFragmentsPerChromosome(resSite="AAGCTT", overhangs5=1,
                                                    chromosomes="chr6",
                                                    genomePack="BSgenome.Hsapiens.UCSC.hg18")
    # --- Annot [] ---
    # Key functions: import, getAnnotatedRestrictionSites, setGenomicFeatures, y_intervals
    ## Annotation of genomic features for LGF normalization
    ## Example on chromosome 6
    ## Load mappability track
    require(rtracklayer)
    ##map_hg18 <- import("wgEncodeCrgMapabilityAlign100mer_chr6.bw",format="BigWig")
    # --- Normlgf [] ---
    # Key functions: normLGF
    ## ## LGF normalization
    ## imr90_500_LGF <- normLGF(imr90_500_chr6annot)
    # --- Normice [] ---
    # Key functions: normICE, mapC, HTClist
    imr90_500_ICE <-  normICE(imr90_500, max_iter=10)
    mapC(HTClist(imr90_500_ICE$chr6chr6), trim.range=.95,
         col.pos=c("white", "orange", "red", "black"))
    # --- Tads [] ---
    # Key functions: extractRegion
    hox <- extractRegion(hic_imr90_40$chr6chr6, chr="chr6", from=50e6, to=58e6)
    plot(hox, maxrange=50, col.pos=c("white", "orange", "red", "black"))
    # --- Di [] ---
    # Key functions: directionalityIndex, ifelse
    di<-directionalityIndex(hox)
    barplot(di, col=ifelse(di>0,"darkred","darkgreen"))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hitc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hitc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hitc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HITC:", paste0("    hitc: ", packageVersion("HiTC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hitc_results.csv
    touch ${prefix}_hitc_output.rds
    echo "BIOC_HITC:" > versions.yml
    echo "    hitc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HITC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HITC(ch_input)

    emit:
    results  = BIOC_HITC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HITC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HITC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HITC.out.versions  // channel: path(versions.yml)
}
