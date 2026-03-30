#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: CoverageView
// This package provides a framework for the visualization of genome coverage profiles. It can be used 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/CoverageView/inst/doc/CoverageView.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("CoverageView")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COVERAGEVIEW {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-coverageview"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-coverageview:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-coverageview:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_coverageview_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_coverageview_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_coverageview_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CoverageBamFile)
    library(CoverageBigWigFile)
    library(jsonlite)

    # --- Example Coveragebamfile [] ---
    # Key functions: CoverageBamFile
    treatBAMfile<-system.file("extdata","treat.bam",package="CoverageView")
    trm<-CoverageBamFile(treatBAMfile,reads_mapped=28564510)
    # --- Example Wigfile [] ---
    # Key functions: CoverageBigWigFile
    treatBigWIGfile<-system.file("extdata","treat.bw",package="CoverageView")
    trm<-CoverageBigWigFile(treatBigWIGfile,reads_mapped=28564510)
    # --- Example Cov.Matrix 1 [] ---
    # Key functions: CoverageBamFile
    ## # get the FoxA1 BAM file for chr19
    ## FoxA1_chr19_BAM_url="http://www.ebi.ac.uk/~ernesto/FoxA1.chr19.bam"
    ## download.file(FoxA1_chr19_BAM_url,"./FoxA1.chr19.bam")
    ## # get the FoxA1 BAM index file
    ## FoxA1_chr19_BAI_url="http://www.ebi.ac.uk/~ernesto/FoxA1.chr19.bam.bai"
    # --- Example Cov.Matrix Profile [] ---
    # Key functions: profile
    draw.profile(FoxA1_chr19,ylab="avg coverage",outfile="FoxA1_chr19.png",
    main="FoxA1 chr19")
    # --- Example Cov.Matrix Heatmap [] ---
    # Key functions: heatmap
    draw.heatmap(FoxA1_chr19,outfile="FoxA1_chr19_heatmap.png")
    # --- Example Cov.Matrix Histone 1 [] ---
    # Key functions: file
    ## # get the sample BAM file for chr19
    ## H3K4me3_BAM_url="http://www.ebi.ac.uk/~ernesto/H3K4me3.chr19.bam"
    ## download.file(H3K4me3_BAM_url,"./H3K4me3.chr19.bam")
    ## # get also the index for the previous file
    ## H3K4me3_BAI_url="http://www.ebi.ac.uk/~ernesto/H3K4me3.chr19.bam.bai"
    # --- Example Cov.Matrix Histone 2 [] ---
    # Key functions: CoverageBamFile
    ## trm<-CoverageBamFile("./H3K4me3.chr19.bam",reads_mapped=864924)
    ## ctl<-CoverageBamFile("./H3K4me3_Control.chr19.bam",reads_mapped=319369)
    # --- Example Cov.Matrix Histone 3 [] ---
    # Key functions: file
    H3K4me3_chr19_bed<-system.file("extdata","H3K4me3.chr19.bed",
    package="CoverageView")
    # --- Example Cov.Matrix Histone 4B [] ---
    # Key functions: data
    data(DF_H3K4me3)
    data(DF_H3K4me3_ctl)
    # --- Example Cov.Matrix Histone 5 [] ---
    # Key functions: profile
    input_list=list(DF_H3K4me3,DF_H3K4me3_ctl)
    draw.profile(data=input_list,ylab="avg coverage",outfile="H3K4me3cmp.png"
    ,main="H3K4me3")
    # --- Example Cov.Matrix Histone 6 [] ---
    # Key functions: heatmap
    input_list=list(DF_H3K4me3,DF_H3K4me3_ctl)
    draw.heatmap(data=input_list,outfile="H3K4me3cmp_heatmap.png")
    # --- Example Cov.Matrix Histone 7 [] ---
    # Key functions: data
    data(DF_H3K36me3)
    data(DF_H3K36me3_control)
    # --- Example Cov.Matrix Histone 8 [] ---
    # Key functions: heatmap
    input_list=list(DF_H3K4me3,DF_H3K4me3_ctl,DF_H3K36me3,DF_H3K36me3_control)
    draw.heatmap(data=input_list,outfile="H3K4me3VSH3K36me3_heatmap.png")
    # --- Example Cov.Matrix Histone 9B [] ---
    # Key functions: data
    data(DF_H3K4me3_nopeaks_ratios)
    # --- Example Cov.Matrix Histone 10 [] ---
    # Key functions: profile
    draw.profile(DF_H3K4me3_nopeaks_ratios,ylab="avg coverage",
    outfile="H3K4me3nopeaks_ratios.png",main="H3K4me3 ratio")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_coverageview_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_coverageview_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_coverageview_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_COVERAGEVIEW:", paste0("    coverageview: ", packageVersion("CoverageView"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coverageview_results.csv
    touch ${prefix}_coverageview_output.rds
    echo "BIOC_COVERAGEVIEW:" > versions.yml
    echo "    coverageview: 0.0.0" >> versions.yml
    """
}


workflow BIOC_COVERAGEVIEW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_COVERAGEVIEW(ch_input)

    emit:
    results  = BIOC_COVERAGEVIEW.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_COVERAGEVIEW.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_COVERAGEVIEW.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_COVERAGEVIEW.out.versions  // channel: path(versions.yml)
}
