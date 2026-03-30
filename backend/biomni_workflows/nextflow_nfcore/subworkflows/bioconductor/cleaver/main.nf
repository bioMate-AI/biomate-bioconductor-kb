#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: cleaver
// In-silico cleavage of polypeptide sequences. The cleavage rules are taken from: http://web.expasy.or
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/cleaver/inst/doc/cleaver.R
// Upstream  : BRAIN
// Downstream: none
//
// Install: BiocManager::install("cleaver")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CLEAVER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-cleaver"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-cleaver:1.44.0--r44_0' :
        'quay.io/biocontainers/bioconductor-cleaver:1.44.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_cleaver_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_cleaver_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_cleaver_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(AAStringSet)
    library(jsonlite)

    # --- Cleave [] ---
    # Key functions: cleave, cleavageRanges, cleavageSites
    ---------------------------------------------------------------------
    ## cleave it
    cleave("LAAGKVEDSD", enzym="trypsin")
    ## get the cleavage ranges
    cleavageRanges("LAAGKVEDSD", enzym="trypsin")
    # --- Cleave [] ---
    # Key functions: cleave, cleavageRanges
    ---------------------------------------------------------------------
    ## miss one cleavage position
    cleave("LAAGKVEDSD", enzym="trypsin", missedCleavages=1)
    cleavageRanges("LAAGKVEDSD", enzym="trypsin", missedCleavages=1)
    ## miss zero or one cleavage positions
    # --- Aastringset [] ---
    # Key functions: AAStringSet, cleave, cleavageRanges, cleavageSites
    ---------------------------------------------------------------------
    ## create AAStringSet object
    p <- AAStringSet(c(gaju="LAAGKVEDSD", pnm="AGEPKLDAGV"))
    ## cleave it
    cleave(p, enzym="trypsin")
    # --- Ws [] ---
    # Key functions: ws, select, setNames
    ---------------------------------------------------------------------
    ## load UniProt.ws library
    library("UniProt.ws")
    ## select species Homo sapiens
    up <- UniProt.ws(taxId=9606)
    # --- Cleave [] ---
    # Key functions: cleave
    ---------------------------------------------------------------------
    cleave(sequences, enzym="pepsin")
    # --- Cleave [] ---
    # Key functions: cleave, getAtomsFromSeq, useBRAIN
    ---------------------------------------------------------------------
    ## load BRAIN library
    library("BRAIN")
    ## cleave insulin
    cleavedInsulin <- cleave(sequences[1], enzym="trypsin")[[1]]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_cleaver_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_cleaver_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_cleaver_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_CLEAVER:", paste0("    cleaver: ", packageVersion("cleaver"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cleaver_results.csv
    touch ${prefix}_cleaver_output.rds
    echo "BIOC_CLEAVER:" > versions.yml
    echo "    cleaver: 0.0.0" >> versions.yml
    """
}


workflow BIOC_CLEAVER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_CLEAVER(ch_input)

    emit:
    results  = BIOC_CLEAVER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_CLEAVER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_CLEAVER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_CLEAVER.out.versions  // channel: path(versions.yml)
}
