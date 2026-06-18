#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OncoSimulR — random_landscape_predictability
// Generate a random fitness landscape, simulate evolution on it, and calculate evolutionary predictability statistics.
// Input: integer, numeric
// Container: quay.io/biocontainers/bioconductor-oncosimulr:4.12.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OncoSimulR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Generate a random fitness landscape using rfitness
//  * 2. [Core Analysis] Convert to fitness effects using allFitnessEffects with genotFitness
//  * 3. [Core Analysis] Simulate population trajectories using oncoSimulPop with keepPhylog = TRUE
//  * 4. [Core Analysis] Calculate predictability measures using LOD, POM, diversityLOD, and diversityPOM

nextflow.enable.dsl = 2

process BIOC_ONCOSIMULR_RANDOM_LANDSCAPE_PREDICTABILITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("OncoSimulR")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library(OncoSimulR)
    
    # Read user inputs from the working directory
    if (!file.exists("integer") || !file.exists("numeric")) {
      stop("Required input files 'integer' and/or 'numeric' are missing in the working directory.")
    }
    
    g <- as.integer(readLines("integer", warn = FALSE)[1])
    c <- as.numeric(readLines("numeric", warn = FALSE)[1])
    
    # 1. Generate a random fitness landscape using rfitness
    rl <- rfitness(g, c = c, min_accessible_genotypes = g)
    
    # 2. Convert to fitness effects and 3. Simulate population trajectories
    simulrl <- oncoSimulPop(10, allFitnessEffects(genotFitness = rl),
                            keepPhylog = TRUE, keepEvery = 1,
                            onlyCancer = TRUE,
                            initSize = 4000,
                            seed = NULL,
                            mc.cores = 2)
    
    # 4. Calculate predictability measures
    divLOD <- diversityLOD(LOD(simulrl))
    divPOM <- diversityPOM(POM(simulrl))
    sampGen <- sampledGenotypes(samplePop(simulrl, typeSample = "whole"))
    
    # Write outputs to files
    saveRDS(rl, "fitness_landscape.rds")
    saveRDS(simulrl, "simulation_population.rds")
    
    metrics_df <- data.frame(
      Metric = c("diversityLOD", "diversityPOM"),
      Value = c(divLOD, divPOM)
    )
    write.csv(metrics_df, "predictability_metrics.csv", row.names = FALSE)
    write.csv(as.data.frame(sampGen), "sampled_genotypes.csv", row.names = TRUE)
    
    # Generate plots safely
    pdf("fitness_landscape.pdf")
    tryCatch({
      plot(rl)
    }, error = function(e) {
      message("Could not plot fitness landscape: ", e\$message)
    })
    dev.off()
    
    pdf("simulation_plots.pdf")
    tryCatch({
      plot(simulrl)
    }, error = function(e) {
      message("Could not plot simulation trajectories: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_ONCOSIMULR_RANDOM_LANDSCAPE_PREDICTABILITY":',
        paste0('    OncoSimulR: ', as.character(packageVersion('OncoSimulR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_random_landscape_predictability.csv versions.yml
    """
}

workflow BIOC_ONCOSIMULR_RANDOM_LANDSCAPE_PREDICTABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ integer, numeric ] ]

    main:
    BIOC_ONCOSIMULR_RANDOM_LANDSCAPE_PREDICTABILITY(ch_input)

    emit:
    tables   = BIOC_ONCOSIMULR_RANDOM_LANDSCAPE_PREDICTABILITY.out.tables
    plots    = BIOC_ONCOSIMULR_RANDOM_LANDSCAPE_PREDICTABILITY.out.plots
    objects  = BIOC_ONCOSIMULR_RANDOM_LANDSCAPE_PREDICTABILITY.out.objects
    versions = BIOC_ONCOSIMULR_RANDOM_LANDSCAPE_PREDICTABILITY.out.versions
}
