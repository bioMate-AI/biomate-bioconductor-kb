#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: methylKit
// methylKit is an R package for DNA methylation analysis and annotation from high-throughput bisulfite
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/methylKit/inst/doc/methylKit.R
// Upstream  : genomation
// Downstream: none
//
// Install: BiocManager::install("methylKit")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHYLKIT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-methylkit"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-methylkit:1.32.1--r44_0' :
        'quay.io/biocontainers/bioconductor-methylkit:1.32.1--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_methylkit_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_methylkit_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_methylkit_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PCASamples)
    library(jsonlite)

    # --- Getmethylationstats [] ---
    # Key functions: getMethylationStats
    ---------------------------------------------------------------------
    getMethylationStats(myobj[[2]],plot=FALSE,both.strands=FALSE)
    # --- Getcoveragestats [] ---
    # Key functions: getCoverageStats
    ---------------------------------------------------------------------
    getCoverageStats(myobj[[2]],plot=TRUE,both.strands=FALSE)
    # --- Filterbycoverage [] ---
    # Key functions: filterByCoverage
    ---------------------------------------------------------------------
    filtered.myobj=filterByCoverage(myobj,lo.count=10,lo.perc=NULL,
                                          hi.count=NULL,hi.perc=99.9)
    # --- Unite [] ---
    # Key functions: unite
    ---------------------------------------------------------------------
    meth=unite(myobj, destrand=FALSE)
    # --- Getcorrelation [] ---
    # Key functions: getCorrelation
    ---------------------------------------------------------------------
    getCorrelation(meth,plot=TRUE)
    # --- Clustersamples [] ---
    # Key functions: clusterSamples
    ---------------------------------------------------------------------
    clusterSamples(meth, dist="correlation", method="ward", plot=TRUE)
    # --- Pcasamples [] ---
    # Key functions: PCASamples
    ---------------------------------------------------------------------
    PCASamples(meth, screeplot=TRUE)
    # --- Frame [] ---
    # Key functions: frame, assocComp, removeComp
    ---------------------------------------------------------------------
    # make some batch data frame
    # this is a bogus data frame
    # we don't have batch information
    # for the example data
    # --- Percmethylation [] ---
    # Key functions: percMethylation, reconstruct
    ---------------------------------------------------------------------
    mat=percMethylation(meth)
    # do some changes in the matrix
    # this is just a toy example
    # ideally you want to correct the matrix
    # --- Calculatediffmeth [] ---
    # Key functions: calculateDiffMeth
    ---------------------------------------------------------------------
    myDiff=calculateDiffMeth(meth)
    # --- Getmethyldiff [] ---
    # Key functions: getMethylDiff
    ---------------------------------------------------------------------
    # get hyper methylated bases
    myDiff25p.hyper=getMethylDiff(myDiff,difference=25,qvalue=0.01,type="hyper")
    #
    # get hypo methylated bases
    # --- Diffmethperchr [] ---
    # Key functions: diffMethPerChr
    ---------------------------------------------------------------------
    diffMethPerChr(myDiff,plot=FALSE,qvalue.cutoff=0.01, meth.cutoff=25)
    # --- Readtranscriptfeatures [] ---
    # Key functions: readTranscriptFeatures, annotateWithGeneParts
    ---------------------------------------------------------------------
    library(genomation)
    # read the gene BED file
    gene.obj=readTranscriptFeatures(system.file("extdata", "refseq.hg18.bed.txt",
                                               package = "methylKit"))
    # --- Readfeatureflank [] ---
    # Key functions: readFeatureFlank, annotateWithFeatureFlank
    ---------------------------------------------------------------------
    # read the shores and flanking regions and name the flanks as shores
    # and CpG islands as CpGi
    # --- Regioncounts [] ---
    # Key functions: regionCounts
    ---------------------------------------------------------------------
    promoters=regionCounts(myobj,gene.obj$promoters)
    head(promoters[[1]])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_methylkit_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_methylkit_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_methylkit_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_METHYLKIT:", paste0("    methylkit: ", packageVersion("methylKit"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylkit_results.csv
    touch ${prefix}_methylkit_output.rds
    echo "BIOC_METHYLKIT:" > versions.yml
    echo "    methylkit: 0.0.0" >> versions.yml
    """
}


workflow BIOC_METHYLKIT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_METHYLKIT(ch_input)

    emit:
    results  = BIOC_METHYLKIT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_METHYLKIT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_METHYLKIT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_METHYLKIT.out.versions  // channel: path(versions.yml)
}
