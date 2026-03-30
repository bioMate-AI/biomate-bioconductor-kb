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
    library(MSA)
    library(jsonlite)

    # --- Initialize [] ---
    # Key functions: path
    library(OSAT)
    inPath <- system.file('extdata', package='OSAT')
    pheno <- read.table(file.path(inPath, 'samples.txt'),
                        header=TRUE, sep="\t", colClasses="factor")
    # --- Tbl1 [] ---
    # Key functions: xtable
    library(xtable)
    print(xtable(summary(pheno), caption="Example Data", label = "tbl:tbl1"), table.placement = "tbp",caption.placement = "top")
    # --- Pheno2 [] ---
    # Key functions: with, frame
    ## with(pheno, as.data.frame(table(SampleType, Race, AgeGrp)))
    # --- Tbl2 [] ---
    # Key functions: xtable, with, frame
    print(xtable(with(pheno, as.data.frame(table(SampleType, Race, AgeGrp))), caption="Data distribution", label = "tbl:tbl2"), table.placement = "tbp",
    caption.placement = "top")
    # --- Gs [] ---
    # Key functions: sample
    gs <- setup.sample(pheno, optimal=c("SampleType", "Race", "AgeGrp"))
    # --- Container [] ---
    # Key functions: container
    gc <- setup.container(IlluminaBeadChip96Plate, 6, batch='plates')
    # --- Gsetup [] ---
    # Key functions: setup
    set.seed(123)    # to create reproducible result
    # demonstration only. nSim=5000 or more are commonly used.
    gSetup <- create.optimized.setup(sample=gs, container=gc, nSim=1000)
    # --- Csvsetup [] ---
    # Key functions: csv, setup
    write.csv(get.experiment.setup(gSetup),
              file="gSetup.csv", row.names=FALSE)
    # --- Csvmsa [] ---
    # Key functions: MSA, csv
    out <- map.to.MSA(gSetup, MSA4.plate)
    write.csv(out, "MSAsetup.csv", row.names = FALSE)
    # --- Optblock [] ---
    # Key functions: sample, setup
    gs2 <- setup.sample(pheno,  strata=c("SampleType"),
              optimal=c("SampleType", "Race", "AgeGrp") )
    set.seed(123)    # to create reproducible result
    # demonstration only. nSim=5000 or more are commonly used.
    gSetup2 <- create.optimized.setup("optimal.block",
    # --- Random [] ---
    # Key functions: getLayout, runif
    set.seed(397)        # an unfortunate choice
    c1 <- getLayout(gc)  # available wells
    c1 <- c1[order(runif(nrow(c1))),] # shuffle randomly
    randomSetup <- cbind(pheno, c1[1:nrow(pheno), ])
         # create a sample assignment
    # --- Random2 [] ---
    # Key functions: test
    multi.chisq.test(randomSetup, grpVar='plates',
          varList=c("SampleType", "Race", "AgeGrp"))
    # --- Gsnew [] ---
    # Key functions: sample
    gs <- setup.sample(pheno, optimal=c("SampleType", "Race", "AgeGrp"),
               strata=c("SampleType"))
    gs
    # --- Gcnew [] ---
    # Key functions: container
    gc <- setup.container(IlluminaBeadChip96Plate, 6,
              batch='plates')
    gc
    # --- setup [] ---
    # Key functions: setup
    gSetup0 <- create.experiment.setup(gs, gc)
    myAssignment <- get.experiment.setup(gSetup0)

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
