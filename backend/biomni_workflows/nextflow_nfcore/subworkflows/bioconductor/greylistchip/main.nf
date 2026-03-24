#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GreyListChIP
// Identify regions of ChIP experiments with high signal in the input, that lead to spurious peaks duri
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GreyListChIP/inst/doc/GreyList-demo.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GreyListChIP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GREYLISTCHIP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-greylistchip"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-greylistchip:1.38.0--r44_0' :
        'quay.io/biocontainers/bioconductor-greylistchip:1.38.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_greylistchip_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_greylistchip_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_greylistchip_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GreyListChIP)
    library(jsonlite)

    # --- Create [] ---
    # Key functions: path, new
    library(GreyListChIP)
    path <- system.file("extra", package="GreyListChIP")
    fn <- file.path(path,"karyotype_chr21.txt")
    gl <- new("GreyList",karyoFile=fn)
    # --- Count [] ---
    # Key functions: countReads
    ## gl <- countReads(gl,"myBamFile.bam")
    # --- Fake [] ---
    # Key functions: rnbinom
    gl@counts <- rnbinom(length(gl@tiles),size=1.08,mu=11.54)
    # --- Threshold [] ---
    # Key functions: calcThreshold
    gl <- calcThreshold(gl,reps=10,sampleSize=1000,p=0.99,cores=1)
    # --- Makegrey [] ---
    # Key functions: makeGreyList
    gl <- makeGreyList(gl,maxGap=16384)
    gl
    # --- Export [] ---
    # Key functions: export
    ## export(gl,con="myGreyList.bed")
    # --- Onestep [] ---
    # Key functions: greyListBS, export
    ## library(BSgenome.Hsapiens.UCSC.hg19)
    ## gl <- greyListBS(BSgenome.Hsapiens.UCSC.hg19,"myBamFile.bam")
    ## export(gl,con="myGreyList.bed")
    # --- Sampledata [] ---
    # Key functions: data
    # Load a pre-built GreyList object named "gl"
    data(greyList)
    print(gl)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_greylistchip_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_greylistchip_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_greylistchip_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GREYLISTCHIP:", paste0("    greylistchip: ", packageVersion("GreyListChIP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_greylistchip_results.csv
    touch ${prefix}_greylistchip_output.rds
    echo "BIOC_GREYLISTCHIP:" > versions.yml
    echo "    greylistchip: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GREYLISTCHIP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GREYLISTCHIP(ch_input)

    emit:
    results  = BIOC_GREYLISTCHIP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GREYLISTCHIP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GREYLISTCHIP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GREYLISTCHIP.out.versions  // channel: path(versions.yml)
}
