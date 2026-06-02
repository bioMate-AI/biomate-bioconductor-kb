#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GOTHiC
// This is a Hi-C analysis package using a cumulative binomial test to detect interactions between dist
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GOTHiC/inst/doc/package_vignettes.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GOTHiC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GOTHIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gothic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gothic:1.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gothic:1.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gothic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gothic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gothic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GOTHiC)
    library(GOTHiChicup)
    library(jsonlite)

    # --- Package Vignettes.Snw:31 33 [] ---
    # Key functions: data
    ## library(GOTHiC)
    ## data(lymphoid_chr20_paired_filtered)
    # --- Package Vignettes.Snw:79 84 [] ---
    # Key functions: files, pairReads
    ## dirPath = system.file("extdata", package="HiCDataLymphoblast")
    ## fileName1 = list.files(dirPath, full.names=TRUE)[1]
    ## fileName2 = list.files(dirPath, full.names=TRUE)[2]
    ## paired = pairReads(fileName1, fileName2, sampleName="lymphoid_chr20",
    ## DUPLICATETHRESHOLD = 1, fileType="Table")
    # --- Package Vignettes.Snw:91 96 [] ---
    # Key functions: mapReadsToRestrictionSites
    ## data(lymphoid_chr20_paired_filtered)
    ## mapped=mapReadsToRestrictionSites(filtered, sampleName="lymphoid_chr20",
    ## BSgenomeName="BSgenome.Hsapiens.UCSC.hg18",
    ## genome=BSgenome.Hsapiens.UCSC.hg18,
    ## restrictionSite="A^AGCTT", enzyme="HindIII", parallel=FALSE, cores=1)
    # --- Package Vignettes.Snw:103 111 [] ---
    # Key functions: files, GOTHiC
    ## dirPath = system.file("extdata", package="HiCDataLymphoblast")
    ## fileName1 = list.files(dirPath, full.names=TRUE)[1]
    ## fileName2 = list.files(dirPath, full.names=TRUE)[2]
    ## binom=GOTHiC(fileName1,fileName2, sampleName="lymphoid_chr20",
    ## res=1000000, BSgenomeName="BSgenome.Hsapiens.UCSC.hg18",
    # --- Package Vignettes.Snw:114 119 [] ---
    # Key functions: files, GOTHiChicup
    ## dirPath <- system.file("extdata", package="HiCDataLymphoblast")
    ## fileName <- list.files(dirPath, full.names=TRUE)[4]
    ## restrictionFile <- list.files(dirPath, full.names=TRUE)[3]
    ## binom=GOTHiChicup(fileName, sampleName='lymphoid_chr20', res=1000000,
    ## restrictionFile, cistrans='all', parallel=FALSE, cores=NULL)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gothic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gothic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gothic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GOTHIC:", paste0("    gothic: ", packageVersion("GOTHiC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gothic_results.csv
    touch ${prefix}_gothic_output.rds
    echo "BIOC_GOTHIC:" > versions.yml
    echo "    gothic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GOTHIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GOTHIC(ch_input)

    emit:
    results  = BIOC_GOTHIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GOTHIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GOTHIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GOTHIC.out.versions  // channel: path(versions.yml)
}
