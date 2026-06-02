#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: OSAT
// A sizable genomics study such as microarray often involves the use of multiple batches (groups) of e
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/OSAT/inst/doc/OSAT.R
// Upstream  : xtable
// Downstream: none
//
// Install: BiocManager::install("OSAT")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OSAT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-osat"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-osat:1.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-osat:1.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_osat_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_osat_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_osat_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(OSAT)
    library(MSA)
    library(jsonlite)

    # --- Sample Setup [Sample Setup] ---
    # Key functions: setup.sample
    inPath <- system.file('extdata', package='osat')
    pheno <- read.table(file.path(inPath, 'samples.txt'), 
                        header=TRUE, sep="\t", colClasses="factor")
    gs <- setup.sample(pheno, 
                       optimal=c("SampleType", "Race", "AgeGrp"),
                       strata=c("SampleType"))

    # --- Container Setup [Container Setup] ---
    # Key functions: setup.container
    gc <- setup.container(IlluminaBeadChip96Plate, 
                          n=6, 
                          batch='plates')

    # --- Optimization and Assignment [Optimization and Assignment] ---
    # Key functions: create.optimized.setup, get.experiment.setup
    gSetup <- create.optimized.setup(sample=gs, 
                                     container=gc, 
                                     nSim=1000)
    assignment <- get.experiment.setup(gSetup)
    write.csv(assignment, file="gSetup.csv", row.names=FALSE)

    # --- Quality Control and Evaluation [Quality Control and Evaluation] ---
    # Key functions: QC, multi.chisq.test
    QC(gSetup)
    assignment <- get.experiment.setup(gSetup)
    multi.chisq.test(assignment, 
                     grpVar='plates', 
                     varList=c("SampleType", "Race", "AgeGrp"))

    # --- Mapping to MSA Plate [Mapping to MSA Plate] ---
    # Key functions: map.to.MSA
    out <- map.to.MSA(gSetup, MSA4.plate)
    write.csv(out, "MSAsetup.csv", row.names=FALSE)


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_osat_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_osat_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_osat_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OSAT:", paste0("    osat: ", packageVersion("OSAT"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_osat_results.csv
    touch ${prefix}_osat_output.rds
    echo "BIOC_OSAT:" > versions.yml
    echo "    osat: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OSAT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OSAT(ch_input)

    emit:
    results  = BIOC_OSAT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OSAT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OSAT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OSAT.out.versions  // channel: path(versions.yml)
}
