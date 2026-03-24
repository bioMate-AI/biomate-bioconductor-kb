#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: Mfuzz
// The Mfuzz package implements noise-robust soft clustering of omics time-series data, including trans
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/Mfuzz/inst/doc/Mfuzz.R
// Upstream  : none
// Downstream: cycle, MultiRNAflow
//
// Install: BiocManager::install("Mfuzz")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MFUZZ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-mfuzz"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-mfuzz:2.66.0--r44_0' :
        'quay.io/biocontainers/bioconductor-mfuzz:2.66.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_mfuzz_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_mfuzz_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_mfuzz_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Mfuzz)
    library(jsonlite)

    # --- Std [] ---
    # Key functions: std
    ##   tmp <- filter.std(yeast.f,min.std=0)
    # --- Standardise [] ---
    # Key functions: standardise
    yeast.s <- standardise(yeast.f)
    # --- Mfuzz [] ---
    # Key functions: mfuzz
    ##  cl <- mfuzz(yeast.s,c=16,m=1.25)
    ##  mfuzz.plot(yeast.s,cl=cl,mfrow=c(4,4),time.labels=seq(0,160,10))
    # --- Mestimate [] ---
    # Key functions: mestimate
    ## m1 <- mestimate(yeast.s)
    ## m1 # 1.15
    # --- Mfuzz [] ---
    # Key functions: mfuzz
    ##    cl2 <- mfuzz(yeast.s,c=16,m=1.35)
    ##    mfuzz.plot(yeast.s,cl=cl2,mfrow=c(4,4),time.labels=seq(0,160,10))
    # --- Overlap [] ---
    # Key functions: overlap
    ## O <- overlap(cl)
    ## Ptmp <- overlap.plot(cl,over=O,thres=0.05)
    # --- Mfuzz [] ---
    # Key functions: mfuzz, overlap
    ## cl3 <- mfuzz(yeast.s,c=10,m=1.25)
    ## mfuzz.plot(yeast.s,cl=cl3,mfrow=c(3,4))
    ## O3 <- overlap(cl3)
    ## overlap.plot(cl3,over=O3,P=Ptmp,thres=0.05)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_mfuzz_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_mfuzz_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_mfuzz_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MFUZZ:", paste0("    mfuzz: ", packageVersion("Mfuzz"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mfuzz_results.csv
    touch ${prefix}_mfuzz_output.rds
    echo "BIOC_MFUZZ:" > versions.yml
    echo "    mfuzz: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MFUZZ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MFUZZ(ch_input)

    emit:
    results  = BIOC_MFUZZ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MFUZZ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MFUZZ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MFUZZ.out.versions  // channel: path(versions.yml)
}
