#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SCAN.UPC
// SCAN is a microarray normalization method to facilitate personalized-medicine workflows. Rather than
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SCAN.UPC/inst/doc/SCAN.vignette.R
// Upstream  : GEOquery, doParallel
// Downstream: none
//
// Install: BiocManager::install("SCAN.UPC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SCAN_UPC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-scan_upc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-scan.upc:2.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-scan.upc:2.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_scan_upc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_scan_upc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_scan_upc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(InstallBrainArrayPackage)
    library(SCAN)
    library(SCAN_TwoColor)
    library(UPC)
    library(UPC_RNASeq)
    library(UPC_TwoColor)
    library(jsonlite)

    # --- Download Geo Direct [] ---
    # Key functions: tempdir, getGEOSuppFiles, path
    ## library(GEOquery)
    ## tmpDir = tempdir()
    ## library(GEOquery)
    ## getGEOSuppFiles("GSM555237", makeDirectory=FALSE, baseDir=tmpDir)
    ## celFilePath = file.path(tmpDir, "GSM555237.CEL.gz")
    # --- Download Normalize [] ---
    # Key functions: SCAN
    ## library(SCAN.UPC)
    ## normalized = SCAN(celFilePath)
    # --- Scan Geo [] ---
    # Key functions: SCAN
    ## normalized = SCAN("GSM555237")
    # --- Download Normalize2 [] ---
    # Key functions: SCAN
    ## normalized = SCAN(celFilePath, outFilePath="output_file.txt")
    # --- Download Brainarray [] ---
    # Key functions: packages
    ## install.packages("hgu95ahsentrezgprobe_15.0.0.tar.gz", repos=NULL, type="source")
    # --- Install Brainarray [] ---
    # Key functions: InstallBrainArrayPackage
    ## pkgName = InstallBrainArrayPackage(celFilePath, "15.0.0", "hs", "entrezg")
    # --- Scan Brainarray [] ---
    # Key functions: SCAN
    ## normalized = SCAN(celFilePath, probeSummaryPackage=pkgName)
    # --- Scan Twocolor Main [] ---
    # Key functions: SCAN_TwoColor
    ## SCAN_TwoColor("GSM1072833", "output_file.txt")
    # --- Upc Microarray [] ---
    # Key functions: UPC, UPC_TwoColor
    ## upc1 = UPC("GSM555237")
    ##
    ## upc2 = UPC_TwoColor("GSM1072833")
    # --- Upc Rnaseq [] ---
    # Key functions: UPC_RNASeq
    ## upc3 = UPC_RNASeq("ReadCounts.txt", "Annotation.txt")
    # --- Scan Parallel [] ---
    # Key functions: registerDoParallel, SCAN
    ## library(doParallel)
    ## registerDoParallel(cores=2)
    ## result = SCAN("GSE22309")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_scan_upc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_scan_upc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_scan_upc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SCAN_UPC:", paste0("    scan_upc: ", packageVersion("SCAN.UPC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_scan_upc_results.csv
    touch ${prefix}_scan_upc_output.rds
    echo "BIOC_SCAN_UPC:" > versions.yml
    echo "    scan_upc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SCAN_UPC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SCAN_UPC(ch_input)

    emit:
    results  = BIOC_SCAN_UPC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SCAN_UPC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SCAN_UPC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SCAN_UPC.out.versions  // channel: path(versions.yml)
}
