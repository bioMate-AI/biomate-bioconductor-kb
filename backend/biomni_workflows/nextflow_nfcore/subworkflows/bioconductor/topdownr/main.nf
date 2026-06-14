#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: topdownr — method_generation
// Generate instrument method XML files to test multiple fragmentation conditions on a Thermo Orbitrap Fusion Lumos.
// Input: target_mz_matrix.csv, TMS2IndependentTemplateForTD.meth
// Container: quay.io/biocontainers/bioconductor-topdownr:1.32.0--r45hdfd78af_0
// R packages: BiocStyle, ggplot2, ranger, topdownr, topdownrdata
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_TOPDOWNR_METHOD_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-topdownr:1.32.0--r45hdfd78af_0"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("BiocStyle", "ggplot2", "ranger", "topdownr", "topdownrdata")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load required library
    library("topdownr")
    
    # --- Read user input files ---
    if (!file.exists("target_mz_matrix.csv")) {
        stop("Required input file 'target_mz_matrix.csv' not found in the working directory.")
    }
    if (!file.exists("TMS2IndependentTemplateForTD.meth")) {
        stop("Required input file 'TMS2IndependentTemplateForTD.meth' not found in the working directory.")
    }
    
    target_mz_df <- read.csv("target_mz_matrix.csv")
    targetMz <- as.matrix(target_mz_df)
    
    # --- Define MS1 settings ---
    ms1 <- expandMs1Conditions(
        FirstMass=400,
        LastMass=1200,
        Microscans=as.integer(10)
    )
    
    # --- Define common settings ---
    common <- list(
        OrbitrapResolution="R120K",
        IsolationWindow=1,
        MaxITTimeInMS=200,
        Microscans=as.integer(40),
        AgcTarget=c(1e5, 5e5, 1e6)
    )
    
    # --- Create settings for different fragmentation conditions ---
    cid <- expandTms2Conditions(
        MassList=targetMz,
        common,
        ActivationType="CID",
        CIDCollisionEnergy=seq(7, 35, 7)
    )
    hcd <- expandTms2Conditions(
        MassList=targetMz,
        common,
        ActivationType="HCD",
        HCDCollisionEnergy=seq(7, 35, 7)
    )
    etd <- expandTms2Conditions(
        MassList=targetMz,
        common,
        ActivationType="ETD",
        ETDReactionTime=as.double(1:2)
    )
    etcid <- expandTms2Conditions(
        MassList=targetMz,
        common,
        ActivationType="ETD",
        ETDReactionTime=as.double(1:2),
        ETDSupplementalActivation="ETciD",
        ETDSupplementalActivationEnergy=as.double(1:2)
    )
    uvpd <- expandTms2Conditions(
        MassList=targetMz,
        common,
        ActivationType="UVPD"
    )
    
    # --- Create experiments with all combinations of the above ---
    exps <- createExperimentsFragmentOptimisation(
        ms1=ms1, cid, hcd, etd, etcid, uvpd,
        groupBy=c("AgcTarget", "replication"), nMs2perMs1=10, scanDuration=0.5,
        replications=2, randomise=TRUE
    )
    
    # Save the generated experiments object to an RDS file
    saveRDS(exps, "experiments_fragment_optimisation.rds")
    
    # --- Write experiments to xml files ---
    writeMethodXmls(exps=exps)
    
    # --- Run XMLMethodChanger (wrapped in tryCatch to handle ---
    tryCatch({
        runXmlMethodChanger(
            modificationXml=list.files(pattern="^method.*\\\\.xml\$"),
            templateMeth="TMS2IndependentTemplateForTD.meth",
            executable="path\\to\\XmlMethodChanger.exe"
        )
    }, error = function(e) {
        message("XMLMethodChanger execution skipped or failed (this is expected if the external executable is not installed):")
        message(e\$message)
    })

    writeLines(c(
        '"BIOC_TOPDOWNR_METHOD_GENERATION":',
        paste0('        topdownr: ', as.character(packageVersion("topdownr")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_method_generation.csv versions.yml
    """
}

workflow BIOC_TOPDOWNR_METHOD_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ target_mz_matrix.csv, TMS2IndependentTemplateForTD.meth ] ]

    main:
    BIOC_TOPDOWNR_METHOD_GENERATION(ch_input)

    emit:
    tables   = BIOC_TOPDOWNR_METHOD_GENERATION.out.tables
    plots    = BIOC_TOPDOWNR_METHOD_GENERATION.out.plots
    objects  = BIOC_TOPDOWNR_METHOD_GENERATION.out.objects
    versions = BIOC_TOPDOWNR_METHOD_GENERATION.out.versions
}
