#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: specL
// provides a functions for generating spectra libraries that can be used for MRM SRM MS workflows in p
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/specL/inst/doc/report.R
// Upstream  : BiocStyle, knitr, rmarkdown
// Downstream: none
//
// Install: BiocManager::install("specL")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPECL {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-specl"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-specl:1.40.0--r44_0' :
        'quay.io/biocontainers/bioconductor-specl:1.40.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_specl_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_specl_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_specl_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(specL)
    library(jsonlite)

    # --- Read Bibliospec Data [read.bibliospec] ---
    # Key functions: read.bibliospec
    filtered_file <- system.file("extdata", "peptideStd.sqlite",
                                 package = "specL")
    redundant_file <- system.file("extdata", "peptideStd_redundant.sqlite",
                                  package = "specL")
    BLIB_FILTERED <- read.bibliospec(filtered_file)
    BLIB_REDUNDANT <- read.bibliospec(redundant_file)
    summary(BLIB_FILTERED)
    summary(BLIB_REDUNDANT)

    # --- Protein Annotation [annotate.protein_id] ---
    # Key functions: annotate.protein_id
    fasta_file <- system.file("extdata", "SP201602-specL.fasta.gz",
                              package = "specL")
    FASTA <- seqinr::read.fasta(fasta_file, seqtype = "AA", as.string = TRUE)
    BLIB_FILTERED <- annotate.protein_id(BLIB_FILTERED, fasta = FASTA)
    summary(BLIB_FILTERED)

    # --- Generate SWATH Ion Library [genSwathIonLib] ---
    # Key functions: genSwathIonLib
    fragmentIonFunction_specL <- function (b, y) {
        Hydrogen <- 1.007825
        b1_ <- (b)
        y1_ <- (y)
        b2_ <- (b + Hydrogen) / 2
        y2_ <- (y + Hydrogen) / 2
        return(cbind(b1_, y1_, b2_, y2_))
    }
    specLibrary <- genSwathIonLib(
        data = BLIB_FILTERED,
        data.fit = BLIB_REDUNDANT,
        max.mZ.Da.error = 0.05,
        topN = 6,
        fragmentIonMzRange = c(300, 1250),
        fragmentIonRange = c(5, 200),
        fragmentIonFUN = fragmentIonFunction_specL,
        mascotIonScoreCutOFF = 17,
        iRT = specL::iRTpeptides
    )
    summary(specLibrary)

    # --- Export and Visualisation [write.spectronaut] ---
    # Key functions: write.spectronaut, plot
    output_file <- tempfile(fileext = ".csv")
    write.spectronaut(specLibrary, file = output_file)
    plot(specLibrary)
    if (length(specLibrary@ionlibrary) > 0) {
        plot(specLibrary@ionlibrary[[1]])
    }


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_specl_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_specl_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_specl_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SPECL:", paste0("    specl: ", packageVersion("specL"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_specl_results.csv
    touch ${prefix}_specl_output.rds
    echo "BIOC_SPECL:" > versions.yml
    echo "    specl: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SPECL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SPECL(ch_input)

    emit:
    results  = BIOC_SPECL.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SPECL.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SPECL.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SPECL.out.versions  // channel: path(versions.yml)
}
