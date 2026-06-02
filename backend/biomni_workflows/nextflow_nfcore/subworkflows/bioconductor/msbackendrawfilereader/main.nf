#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: MsBackendRawFileReader
// implements a MsBackend for the Spectra package using Thermo Fisher Scientific's NewRawFileReader .Ne
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/MsBackendRawFileReader/inst/doc/MsBackendRawFileReader.R
// Upstream  : BiocParallel, ExperimentHub, MsBackendMgf, Spectra, mzR
// Downstream: none
//
// Install: BiocManager::install("MsBackendRawFileReader")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MSBACKENDRAWFILEREADER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-msbackendrawfilereader"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-msbackendrawfilereader:1.12.0--r44_0' :
        'quay.io/biocontainers/bioconductor-msbackendrawfilereader:1.12.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_msbackendrawfilereader_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_msbackendrawfilereader_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_msbackendrawfilereader_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ExperimentHub)
    library(MsBackendRawFileReader)
    library(jsonlite)

    # --- Scan Filtering [] ---
    # Key functions: filterScan
    filtered_be <- MsBackendRawFileReader::filterScan(
        beRaw,
        "FTMS + c NSI Full ms2 487.2567@hcd27.00 [100.0000-1015.0000]"
    )


    # --- Spectra Export [] ---
    # Key functions: export
    mgf_file <- tempfile(fileext = ".mgf")
    map <- c(
        custom = "TITLE",
        msLevel = "CHARGE",
        scanIndex = "SCANS",
        precursorMz = "PEPMASS",
        rtime = "RTINSECONDS"
    )
    MsBackendMgf::export(
        Spectra::Spectra(filtered_be),
        backend = MsBackendMgf::MsBackendMgf(),
        file = mgf_file,
        map = map
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_msbackendrawfilereader_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_msbackendrawfilereader_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_msbackendrawfilereader_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MSBACKENDRAWFILEREADER:", paste0("    msbackendrawfilereader: ", packageVersion("MsBackendRawFileReader"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_msbackendrawfilereader_results.csv
    touch ${prefix}_msbackendrawfilereader_output.rds
    echo "BIOC_MSBACKENDRAWFILEREADER:" > versions.yml
    echo "    msbackendrawfilereader: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MSBACKENDRAWFILEREADER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MSBACKENDRAWFILEREADER(ch_input)

    emit:
    results  = BIOC_MSBACKENDRAWFILEREADER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MSBACKENDRAWFILEREADER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MSBACKENDRAWFILEREADER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MSBACKENDRAWFILEREADER.out.versions  // channel: path(versions.yml)
}
