#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: appreci8R
// The appreci8R is an R version of our appreci8-algorithm - A Pipeline for PREcise variant Calling Int
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/appreci8R/inst/doc/appreci8R.R
// Upstream  : Biostrings, GenomicRanges
// Downstream: none
//
// Install: BiocManager::install("appreci8R")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_APPRECI8R {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-appreci8r"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-appreci8r:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-appreci8r:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(plot_object)

    output:
    tuple val(meta), path("${meta.id}_appreci8r_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_appreci8r_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_appreci8r_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(appreci8R)
    library(jsonlite)


    # --- 4 [] ---
    # Key functions: read.table, filterTarget, extdata, appreci8R
    output_folder<-""
    target<-data.frame(chr = c("2","4","12","17","21","X"),
                       start = c(25469500,106196950,12046280,7579470,36164400,15838363),
                       end = c(25469510,106196960,12046350,7579475,36164410,15838366))
    target
    caller_folder <- system.file("extdata", package = "appreci8R")

    #Input data Sample1:
    read.table(paste(caller_folder, "/Sample1.rawMutations.vcf", sep=""),
               header = FALSE, sep = "\t", stringsAsFactors = FALSE)

    # --- 5 [] ---
    # Key functions: normalize, sample2
    output_folder <- ""
    caller_name <- ""
    sample1 <- data.frame(SampleID = c("Sample1","Sample1","Sample1"),
                          Chr = c("2","17","X"),
                          Pos = c(25469502,7579472,15838366),
                          Ref = c("CAG","G","C"),
                          Alt = c("TAT","C","T,A"),
                          stringsAsFactors = FALSE)
    # --- 6 [] ---
    # Key functions: GRanges, IRanges, annotate, coding, spliceSite, nonsynonymous, frameshift, nonsense
    library(GenomicRanges)
    output_folder <- ""
    caller_name <- ""
    input <- GRanges(seqnames = c("2","X","4","21"),
                     ranges = IRanges(start = c (25469504,15838366,106196951,36164405),
                                      end = c (25469504,15838366,106196951,36164405)),
                     SampleID = c("Sample1","Sample1","Sample2","Sample2"),
                     Ref = c("G","C","A","G"),
                     Alt = c("T","A","G","T"))
    #Input:

    # --- 7 [] ---
    # Key functions: GRangesList, combineOutput
    output_folder <- ""
    caller_name <- ""

    #Input:
    gatk <- annotated[c(1,3),]
    varscan <- annotated[c(2,3),]
    annotated<-GRangesList()
    annotated[[1]]<-gatk
    annotated[[2]]<-varscan
    annotated

    # --- 8 [] ---
    # Key functions: evaluateCovAndBQ, extdata, appreci8R
    output_folder <- ""
    bam_folder <- system.file("extdata", package = "appreci8R")
    bam_folder <- paste(bam_folder, "/", sep="")

    #Input:
    combined

    filtered<-evaluateCovAndBQ(output_folder, combined, bam_folder, bq_diff = 20,
                               vaf = 0.001)
    filtered

    # --- 9 [] ---
    # Key functions: determineCharacteristics
    output_folder <- ""

    #Input:
    filtered

    characteristics <- determineCharacteristics(output_folder, filtered,
                                                predict = "Provean")
    characteristics

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_appreci8r_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_appreci8r_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_appreci8r_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_APPRECI8R:", paste0("    appreci8r: ", packageVersion("appreci8R"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_appreci8r_results.csv
    touch ${prefix}_appreci8r_output.rds
    echo "BIOC_APPRECI8R:" > versions.yml
    echo "    appreci8r: 0.0.0" >> versions.yml
    """
}


workflow BIOC_APPRECI8R_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(plot_object) ]

    main:
    BIOC_APPRECI8R(ch_input)

    emit:
    results  = BIOC_APPRECI8R.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_APPRECI8R.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_APPRECI8R.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_APPRECI8R.out.versions  // channel: path(versions.yml)
}
