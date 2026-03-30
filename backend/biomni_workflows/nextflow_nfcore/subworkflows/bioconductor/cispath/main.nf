#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cisPath
// cisPath is an R package that uses web browsers to visualize and manage protein-protein interaction n
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cisPath/inst/doc/cisPath.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("cisPath")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CISPATH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cispath"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cispath:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cispath:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cispath_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cispath_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cispath_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(cisPath)
    library(jsonlite)

    # --- Example1 [] ---
    # Key functions: path, tempdir, getMappingFile
    library(cisPath)
      sprotFile <- system.file("extdata", "uniprot_sprot_human10.dat",
                                                package="cisPath")
      mappingFile <- file.path(tempdir(), "mappingFile.txt")
      getMappingFile(sprotFile, output=mappingFile)
    # --- Example2 [] ---
    # Key functions: path, tempdir, formatSTRINGPPI
    STRINGPPI <- file.path(tempdir(), "STRINGPPI.txt")
      fileFromSTRING <- system.file("extdata", "protein.links.txt",
                                                 package="cisPath")
      formatSTRINGPPI(fileFromSTRING, mappingFile, "9606", output=STRINGPPI, 700)
    # --- Example3 1 [] ---
    # Key functions: path, tempdir, formatSIFfile
    input <- system.file("extdata", "Homo_sapiens_PINA2.sif", package="cisPath")
      PINA2PPI <- file.path(tempdir(), "PINA2PPI.txt")
      formatSIFfile(input, mappingFile, output=PINA2PPI)
    # --- Example3 2 [] ---
    # Key functions: path, tempdir, formatPINAPPI
    input <- system.file("extdata", "Homo_sapiens_PINA100.txt", package="cisPath")
      PINAPPI <- file.path(tempdir(), "PINAPPI.txt")
      formatPINAPPI(input, output=PINAPPI)
    # --- Example4 [] ---
    # Key functions: path, tempdir, formatiRefIndex
    input <- system.file("extdata", "9606.mitab.100.txt", package="cisPath")
      iRefIndex <- file.path(tempdir(), "iRefIndex.txt")
      formatiRefIndex(input, output=iRefIndex)
    # --- Example5 [] ---
    # Key functions: path, tempdir, combinePPI
    output <- file.path(tempdir(), "allPPI.txt")
      combinePPI(c(PINA2PPI, iRefIndex, STRINGPPI), output)
    # --- Example6 [] ---
    # Key functions: path, tempdir, networkView
    infoFile <- system.file("extdata", "PPI_Info.txt", package="cisPath")
      outputDir <- file.path(tempdir(), "networkView")
      networkView(infoFile, c("MAGI1","TP53BP2","TP53", "PTEN"), outputDir,
                                       FALSE, c(1,1,1,0), displayMore=TRUE)
    # --- Example7 [] ---
    # Key functions: path, tempdir, networkView
    infoFile <- system.file("extdata", "PPI_Info.txt", package="cisPath")
      outputDir <- file.path(tempdir(), "networkView2")
      inputFile <- system.file("extdata", "networkView.txt", package="cisPath")
      rt <- read.table(inputFile, sep=",", comment.char="", header=TRUE)
      proteins <- as.vector(rt[,1])
    # --- Example8 [] ---
    # Key functions: path, tempdir, cisPath
    infoFile <- system.file("extdata", "PPI_Info.txt", package="cisPath")
      outputDir <- file.path(tempdir(), "TP53_example1")
      results <- cisPath(infoFile, outputDir, "TP53", c("MAGI1", "GH1"),
                                                           byStep=TRUE)
    # --- Example9 [] ---
    # Key functions: path, tempdir, cisPath
    infoFile <- system.file("extdata", "PPI_Info.txt", package="cisPath")
      outputDir <- file.path(tempdir(), "TP53_example2")
      results <- cisPath(infoFile, outputDir, "TP53",
                         targetProteins=c("Q96QZ7", "P01241"), swissProtID=TRUE)
      results
    # --- Example10 [] ---
    # Key functions: path, tempdir, cisPath
    infoFile <- system.file("extdata", "PPI_Info.txt", package="cisPath")
      outputDir <- file.path(tempdir(), "TP53_example3")
      results <- cisPath(infoFile, outputDir, "TP53")
      results
    # --- Example11 [] ---
    # Key functions: path, tempdir, cisPath
    infoFile <- system.file("extdata", "PPI_Info.txt", package="cisPath")
      outputDir <- file.path(tempdir(), "cisPathResult")
      results <- cisPath(infoFile, outputDir)
    # --- Example12 [] ---
    # Key functions: create, path, cisPath
    ##   outputDir <- "/home/user/TP53"
    ##   # Create the output directory
    ##   dir.create(outputDir, showWarnings = FALSE, recursive = TRUE)
    ##   # infoFile: site where the PPI data file will be saved.
    ##   infoFile <- file.path(outputDir, "Homo_sapiens_PPI.txt")
    # --- Example13 [] ---
    # Key functions: path, tempdir, easyEditor
    outputDir <- file.path(tempdir(), "easyEditor")
      easyEditor(outputDir)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cispath_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cispath_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cispath_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CISPATH:", paste0("    cispath: ", packageVersion("cisPath"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cispath_results.csv
    touch ${prefix}_cispath_output.rds
    echo "BIOC_CISPATH:" > versions.yml
    echo "    cispath: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CISPATH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CISPATH(ch_input)

    emit:
    results  = BIOC_CISPATH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CISPATH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CISPATH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CISPATH.out.versions  // channel: path(versions.yml)
}
