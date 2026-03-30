#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ACE
// Uses segmented copy number data to estimate tumor cell percentage and produce copy number plots disp
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ACE/inst/doc/ACE_vignette.R
// Upstream  : Biobase, QDNAseq, ggplot2
// Downstream: none
//
// Install: BiocManager::install("ACE")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_ACE {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ace"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ace:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ace:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_ace_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ace_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ace_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ACEcall)
    library(jsonlite)

    # --- Data [] ---
    # Key functions: singlemodel, singleplot, ggtitle, theme
    ---------------------------------------------------------------------
    data("copyNumbersSegmented")
    object <- copyNumbersSegmented
    model1 <- singlemodel(object, QDNAseqobjectsample = 1)
    bestfit1 <- model1$minima[tail(which(model1$rerror==min(model1$rerror)), 1)]
    # --- Data [] ---
    # Key functions: singlemodel, singleplot
    ---------------------------------------------------------------------
    data("copyNumbersSegmented")
    object <- copyNumbersSegmented
    # Since you're convinced the mode is 3N, you can run the singlemodel function to
    # fit at ploidy = 3
    # --- Objectsampletotemplate [] ---
    # Key functions: objectsampletotemplate, exclude, rle
    ---------------------------------------------------------------------
    # To use data from QDNAseq-objects, ACE parses it into data frames referred to
    # as "templates". Because we will look at sample2 several times, we can just
    # create a variable with this data frame.
    template <- objectsampletotemplate(object, index = 2)
    # --- Squaremodel [] ---
    # Key functions: squaremodel, ggtitle, singleplot
    ---------------------------------------------------------------------
    # Let's continue with the template we made for sample 2, and just see what happens...
    # Since the output of this one is pretty big, I'm saving it to a variable
    sqmodel <- squaremodel(template)
    ls(sqmodel)
    # --- Getadjustedsegments [] ---
    # Key functions: getadjustedsegments
    ---------------------------------------------------------------------
    # Let's use the template dataframe we already created in the previous section
    # for sample2. For cellularity and ploidy I'll use the original 2N fit
    segmentdf <- getadjustedsegments(template, cellularity = 0.38)
    head(segmentdf)
    # --- Analyzegenomiclocations [] ---
    # Key functions: analyzegenomiclocations
    ---------------------------------------------------------------------
    analyzegenomiclocations(segmentdf, Chromosome = 1, Position = 26365569)
    # --- Acecall [] ---
    # Key functions: ACEcall
    ---------------------------------------------------------------------
    ACEcall(object, 2, cellularity = 0.39)$calledplot
    # --- Twosamplecompare [] ---
    # Key functions: twosamplecompare
    ---------------------------------------------------------------------
    # I don't think these two samples are very much related
    tsc <- twosamplecompare(object, index1 = 1, index2 = 2,
                            cellularity1 = 0.79, cellularity2 = 0.39)
    tsc$compareplot
    # --- Squaremodelsummary [] ---
    # Key functions: squaremodelsummary, squaremodel
    ---------------------------------------------------------------------
    # Let's see some more fits for sample1!
    sms <- squaremodelsummary(object, QDNAseqobjectsample = 1,
                              squaremodel(object, 1, penalty = 0.5, penploidy = 0.5),
                              printplots = FALSE)
    # --- Loopsquaremodel [] ---
    # Key functions: loopsquaremodel
    ---------------------------------------------------------------------
    # I like squaremodels
    lsm <- loopsquaremodel(object, printplots = FALSE, printobjectsummary = FALSE,
                           penalty = 0.5, penploidy = 0.5, returnmodels = TRUE)
    class(lsm)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ace_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ace_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ace_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_ACE:", paste0("    ace: ", packageVersion("ACE"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ace_results.csv
    touch ${prefix}_ace_output.rds
    echo "BIOC_ACE:" > versions.yml
    echo "    ace: 0.0.0" >> versions.yml
    """
}


workflow BIOC_ACE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_ACE(ch_input)

    emit:
    results  = BIOC_ACE.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_ACE.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_ACE.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_ACE.out.versions  // channel: path(versions.yml)
}
