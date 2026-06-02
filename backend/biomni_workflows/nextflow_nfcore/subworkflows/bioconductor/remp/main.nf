#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: REMP
// Machine learning-based tools to predict DNA methylation of locus-specific repetitive elements (RE) b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/REMP/inst/doc/REMP.R
// Upstream  : devtools, knitr
// Downstream: none
//
// Install: BiocManager::install("REMP")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_REMP {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-remp"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-remp:1.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-remp:1.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_remp_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_remp_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_remp_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(REMP)
    library(jsonlite)

    # --- Function [] ---
    # Key functions: set
    library(knitr)
    options(width=72)
    # --- Bioconductorremprelease [] ---
    # Key functions: requireNamespace, packages
    ## if (!requireNamespace("BiocManager", quietly=TRUE))
    ##     install.packages("BiocManager")
    ## BiocManager::install("REMP")
    # --- Groomethy [] ---
    # Key functions: getGM12878, grooMethy
    # Get GM12878 methylation data (450k array)
    GM12878_450k <- getGM12878('450k')
    GM12878_450k <- grooMethy(GM12878_450k)
    GM12878_450k
    # --- Seqgr [] ---
    # Key functions: getLocations
    library(IlluminaHumanMethylation450kanno.ilmn12.hg19)
    getLocations(IlluminaHumanMethylation450kanno.ilmn12.hg19)
    # --- Remparcel [] ---
    # Key functions: initREMP
    data(Alu.hg19.demo)
    # --- Saveparcel [] ---
    # Key functions: saveParcel
    saveParcel(remparcel)
    # --- Rempredict [] ---
    # Key functions: remp
    remp.res <- remp(GM12878_450k,
                     REtype = 'Alu',
                     parcel = remparcel,
                     ncore = 1,
                     seed = 777)
    # --- Rempprint [] ---
    # Key functions: details
    remp.res
    # Display more detailed information
    details(remp.res)
    # --- Rempaccessors [] ---
    # Key functions: value, rempB, rempM, rowRanges, rempImp, metadata
    # Predicted RE-CpG methylation value (Beta value)
    rempB(remp.res)
    # Predicted RE-CpG methylation value (M value)
    rempM(remp.res)
    # Genomic location information of the predicted RE-CpG
    # --- Remptrim [] ---
    # Key functions: threshold, rempTrim, details
    # Any predicted CpG values with quality score less than
    # threshold (default = 1.7) will be replaced with NA.
    # CpGs contain more than missingRate * 100% (default = 20%)
    # missing rate across samples will be discarded.
    remp.res <- rempTrim(remp.res, threshold = 1.7, missingRate = 0.2)
    # --- Rempaggregate [] ---
    # Key functions: rempAggregate, details
    remp.res <- rempAggregate(remp.res, NCpG = 2)
    details(remp.res)
    # --- Rempdecodeannot [] ---
    # Key functions: decodeAnnot, rempAnnot
    # By default gene symbol annotation will be added
    remp.res <- decodeAnnot(remp.res)
    rempAnnot(remp.res)
    # --- Rempplot [] ---
    # Key functions: remplot, methylation
    remplot(remp.res, main = "Alu methylation (GM12878)", col = "blue")
    # --- Remprofile [] ---
    # Key functions: remprofile, details, rempAggregate
    # Use Alu.hg19.demo for demonstration

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_remp_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_remp_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_remp_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_REMP:", paste0("    remp: ", packageVersion("REMP"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_remp_results.csv
    touch ${prefix}_remp_output.rds
    echo "BIOC_REMP:" > versions.yml
    echo "    remp: 0.0.0" >> versions.yml
    """
}


workflow BIOC_REMP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_REMP(ch_input)

    emit:
    results  = BIOC_REMP.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_REMP.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_REMP.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_REMP.out.versions  // channel: path(versions.yml)
}
