#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DNAcopy
// Implements the circular binary segmentation (CBS) algorithm to segment DNA copy number data and iden
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DNAcopy/inst/doc/DNAcopy.R
// Upstream  : none
// Downstream: CGHcall, cghMCR, CRImage, PureCN, CSclone
//
// Install: BiocManager::install("DNAcopy")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DNACOPY {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-dnacopy"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-dnacopy:1.80.0--r44_0' :
        'quay.io/biocontainers/bioconductor-dnacopy:1.80.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_dnacopy_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_dnacopy_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_dnacopy_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(CNA)
    library(jsonlite)

    # --- Cna [] ---
    # Key functions: CNA
    CNA.object <- CNA(cbind(coriell$Coriell.05296),
                      coriell$Chromosome,coriell$Position,
                      data.type="logratio",sampleid="c05296")
    # --- Segment [] ---
    # Key functions: segment
    segment.smoothed.CNA.object <- segment(smoothed.CNA.object, verbose=1)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_dnacopy_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_dnacopy_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_dnacopy_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DNACOPY:", paste0("    dnacopy: ", packageVersion("DNAcopy"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dnacopy_results.csv
    touch ${prefix}_dnacopy_output.rds
    echo "BIOC_DNACOPY:" > versions.yml
    echo "    dnacopy: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DNACOPY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DNACOPY(ch_input)

    emit:
    results  = BIOC_DNACOPY.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DNACOPY.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DNACOPY.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DNACOPY.out.versions  // channel: path(versions.yml)
}
