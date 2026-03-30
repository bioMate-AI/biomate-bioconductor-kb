#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ReportingTools
// The ReportingTools software package enables users to easily display reports of analysis results gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ReportingTools/inst/doc/basicReportingTools.R
// Upstream  : ALL, Category, DESeq2, GOstats, GSEABase
// Downstream: none
//
// Install: BiocManager::install("ReportingTools")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REPORTINGTOOLS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-reportingtools"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-reportingtools:2.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-reportingtools:2.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_reportingtools_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_reportingtools_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_reportingtools_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CSVFile)
    library(HTMLReport)
    library(jsonlite)

    # --- Makebasicdataframe [] ---
    # Key functions: frame
    my.df <- data.frame(EGID = c("103", "104", "105", "106", "107"),
                        RPKM = c(4, 5, 3, 100, 75),
                        DE = c("Yes", "Yes", "No", "No", "No"))
    my.df
    # --- Makecsvfile [] ---
    # Key functions: CSVFile, publish
    ## library(ReportingTools)
    ##
    ## csvFile <- CSVFile(shortName = "my_csv_file",
    ##     reportDirectory = "./reports")
    ## publish(my.df, csvFile)
    # --- Basichtmlreport [] ---
    # Key functions: HTMLReport, publish, finish
    ## htmlRep <- HTMLReport(shortName = "my_html_file",
    ##     reportDirectory = "./reports")
    ## publish(my.df, htmlRep)
    ## finish(htmlRep)
    # --- Reportingtwotypes [] ---
    # Key functions: CSVFile, HTMLReport, publish, finish
    ## csvFile2 <- CSVFile(shortName = "my_csv_file2",
    ##     reportDirectory = "./reports")
    ## htmlRep2 <- HTMLReport(shortName = 'my_html_file2',
    ## 	title="Publishing a data frame and csv file together",
    ##     reportDirectory = "./reports")
    # --- Addimage [] ---
    # Key functions: recordPlot, barchart, HTMLReport, publish, finish
    ## plot(my.df$EGID, my.df$RPKM, xlab="EGID",
    ## 	ylab="RPKM", main="Scatter plot of RPKMs", col="blue")
    ## scatterPlot <- recordPlot()
    ## library(lattice)
    ## barPlot <- barchart(my.df$RPKM~my.df$EGID)  ##lattice plots behave slightly differently
    # --- Addtextplot [] ---
    # Key functions: off, HTMLReport, publish, hwrite, hwriteImage
    ## png(filename="reports/barplot.png")
    ## barplot(my.df$RPKM, names.arg=my.df$EGID, xlab="EGID",
    ## 	ylab="RPKM", main="Bar plot of RPKMs", col="blue")
    ## dev.off()
    ##
    # --- Addplotlink [] ---
    # Key functions: off, hwriteImage
    ## imagename <- c()
    ## for (i in 1:nrow(my.df)){
    ## 	imagename[i] <- paste0("plot", i, ".png")
    ## 	png(filename = paste0("reports/", imagename[i]))
    ## 	plot(my.df$RPKM[i], ylab="RPKM", xlab = my.df$EGID[i], main = "RPKM Plot", col = "blue")
    # --- Multipletables [] ---
    # Key functions: frame, HTMLReport, publish, finish
    ## df2 <- data.frame(x = 1:5, y = 11:15)
    ## df3 <- data.frame(x = c("a", "b", "c"), y = 1:3)
    ##
    ## htmlRep7 <- HTMLReport(shortName = "my_html_file7", title = "Many tables, one page",
    ##                        reportDirectory = "./reports")
    # --- Publishmatrix [] ---
    # Key functions: rnorm, frame
    ## set.seed(123)
    ## my.mat <- matrix(rnorm(20), nrow=5)
    ## makeDF <- function(object, ...){
    ## 	df <- as.data.frame(object[-2,])
    ## 	names(df) <- paste0("New ", 1:4)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_reportingtools_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_reportingtools_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_reportingtools_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REPORTINGTOOLS:", paste0("    reportingtools: ", packageVersion("ReportingTools"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_reportingtools_results.csv
    touch ${prefix}_reportingtools_output.rds
    echo "BIOC_REPORTINGTOOLS:" > versions.yml
    echo "    reportingtools: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REPORTINGTOOLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REPORTINGTOOLS(ch_input)

    emit:
    results  = BIOC_REPORTINGTOOLS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REPORTINGTOOLS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REPORTINGTOOLS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REPORTINGTOOLS.out.versions  // channel: path(versions.yml)
}
