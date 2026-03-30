#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: TEQC
// Target capture experiments combine hybridization-based (in solution or on microarrays) capture and e
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/TEQC/inst/doc/TEQC.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("TEQC")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TEQC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-teqc"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-teqc:4.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-teqc:4.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_teqc_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_teqc_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_teqc_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GC)
    library(jsonlite)

    # --- target [] ---
    # Key functions: target
    ft <- fraction.target(targets, genome = "hg38")
    ft
    # --- Reads [] ---
    # Key functions: reads
    reads <- get.reads(paste(exptPath, "ExampleSet_Reads.bed", sep="/"),
          chrcol = 1, startcol = 2, endcol = 3, idcol = 4, zerobased = F, skip = 0)
    reads
    # --- reads2pairs [] ---
    # Key functions: reads2pairs
    readpairs <- reads2pairs(reads)
    readpairs
    # --- target [] ---
    # Key functions: target
    fr <- fraction.reads.target(reads, targets)
    fr
    # --- Withoffset [] ---
    # Key functions: target
    fraction.reads.target(reads, targets, Offset=100)
    # --- Fracpairs [] ---
    # Key functions: target
    fraction.reads.target(readpairs, targets)
    # --- target [] ---
    # Key functions: target
    Coverage <- coverage.target(reads, targets, perTarget=T, perBase=T)
    Coverage
    targets2 <- Coverage$targetCoverages
    # --- Readspertarget [] ---
    # Key functions: readsPerTarget
    targets2 <- readsPerTarget(reads, targets2)
    targets2
    # --- Coverageuniformity [] ---
    # Key functions: uniformity
    coverage.uniformity(Coverage)
    # --- baits [] ---
    # Key functions: baits
    baitsfile <- paste(exptPath, "ExampleSet_Baits.txt", sep="/")
    baits <- get.baits(baitsfile, chrcol=3, startcol=4, endcol=5, seqcol=2)
    # --- Coveragegc [] ---
    # Key functions: GC
    coverage.GC(Coverage$coverageAll, baits, pch=16, cex=1.5)
    # --- wigfiles [] ---
    # Key functions: wigfiles
    ## make.wigfiles(Coverage$coverageAll)
    # --- Cov1 [] ---
    # Key functions: target
    coverage.target(reads.collapsed, targets, perBase=F, perTarget=F)
    # --- Cov2 [] ---
    # Key functions: target
    coverage.target(reads.collapsed.pairs, targets, perBase=F, perTarget=F)
    # --- Newsample [] ---
    # Key functions: sample, target
    r <- sample(length(reads), 0.1 * length(reads))
    reads2 <- reads[-r,,drop=T]
    Coverage2 <- coverage.target(reads2, targets, perBase=T)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_teqc_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_teqc_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_teqc_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_TEQC:", paste0("    teqc: ", packageVersion("TEQC"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_teqc_results.csv
    touch ${prefix}_teqc_output.rds
    echo "BIOC_TEQC:" > versions.yml
    echo "    teqc: 0.0.0" >> versions.yml
    """
}


workflow BIOC_TEQC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_TEQC(ch_input)

    emit:
    results  = BIOC_TEQC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_TEQC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_TEQC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_TEQC.out.versions  // channel: path(versions.yml)
}
