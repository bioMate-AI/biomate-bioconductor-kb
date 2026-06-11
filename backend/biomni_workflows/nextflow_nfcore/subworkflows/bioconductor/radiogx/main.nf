#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RadioGx — dose_response_modeling_and_metrics
// Fit linear-quadratic models to radiation dose-response data, compute radio-sensitivity metrics (SF2, D10, AUC), and plot dose-response curves.
// Input: radiation_doses.csv, survival_fractions.csv
// Container: quay.io/biocontainers/bioconductor-radiogx:2.14.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RadioGx
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Fit a linear-quadratic model to dose and survival fraction data using linearQuadraticModel
//  * 2. [Core Analysis] Compute surviving fraction at 2 Gy using computeSF2
//  * 3. [Core Analysis] Compute dose at 10% survival using computeD10
//  * 4. [Core Analysis] Compute area under the dose-response curve using computeAUC
//  * 5. [Visualization & Output] Plot the dose-response curve using doseResponseCurve

nextflow.enable.dsl = 2

process BIOC_RADIOGX_DOSE_RESPONSE_MODELING_AND_METRICS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("RadioGx")
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
    
    # Load required libraries
    library(RadioGx)
    
    # 1. Read user input files
    doses_data <- read.csv("radiation_doses.csv", header = TRUE)
    radiationDoses <- as.numeric(doses_data[[1]])
    
    sf_data <- read.csv("survival_fractions.csv", header = TRUE)
    survivalFractions <- as.numeric(sf_data[[1]])
    
    # 2. Fit linear-quadratic model
    LQmodel <- linearQuadraticModel(D=radiationDoses,
                                    SF=survivalFractions)
    print(LQmodel)
    
    # Save LQmodel parameters to RDS
    saveRDS(LQmodel, "LQmodel.rds")
    
    # 3. Compute radio-sensitivity metrics
    survFracAfter2Units <- computeSF2(pars=LQmodel)
    print(survFracAfter2Units)
    
    dose10PercentSurv <- computeD10(pars=LQmodel)
    print(dose10PercentSurv)
    
    areaUnderDoseRespCurve <- RadioGx::computeAUC(D=radiationDoses, pars=LQmodel, lower=0,
                                         upper=1)
    print(areaUnderDoseRespCurve)
    
    # Save computed metrics to a CSV file
    metrics_df <- data.frame(
      Metric = c("SF2", "D10", "AUC_0_1"),
      Value = c(survFracAfter2Units, dose10PercentSurv, areaUnderDoseRespCurve),
      stringsAsFactors = FALSE
    )
    write.csv(metrics_df, "radio_sensitivity_metrics.csv", row.names = FALSE)
    
    # 4. Plot dose-response curves and save to PDF
    pdf("dose_response_curves.pdf", width = 7, height = 7)
    
    # Plot 1: Using raw data lists
    doseResponseCurve(
      Ds=list("Experiment 1" = radiationDoses),
      SFs=list("Experiment 1" = survivalFractions),
      plot.type="Both"
    )
    
    # Plot 2: Using a constructed RadioSet to avoid using bundled demo datasets
    tryCatch({
      # Construct minimal components for a valid RadioSet
      cell <- data.frame(
        sampleid = paste0("cell", 1:5),
        row.names = paste0("cell", 1:5),
        stringsAsFactors = FALSE
      )
      
      radiation <- data.frame(
        radiation.types = "radiation",
        row.names = "radiation",
        stringsAsFactors = FALSE
      )
      
      sensitivityInfo <- data.frame(
        sampleid = paste0("cell", 1:5),
        radiation.types = rep("radiation", 5),
        row.names = paste0("cell", 1:5),
        stringsAsFactors = FALSE
      )
      
      sensRaw <- array(
        NA,
        dim = c(5, length(radiationDoses), 2),
        dimnames = list(
          paste0("cell", 1:5),
          paste0("dose", seq_along(radiationDoses)),
          c("Dose", "Viability")
        )
      )
      for (i in 1:5) {
        sensRaw[i, , "Dose"] <- radiationDoses
        sensRaw[i, , "Viability"] <- survivalFractions
      }
      
      sensProf <- matrix(
        0,
        nrow = 5,
        ncol = 1,
        dimnames = list(paste0("cell", 1:5), "AUC")
      )
      
      # Instantiate the RadioSet object
      clevelandSmall <- RadioSet(
        name = "ClevelandMock",
        molecularProfiles = list(),
        cell = cell,
        radiation = radiation,
        sensitivityInfo = sensitivityInfo,
        sensitivityRaw = sensRaw,
        sensitivityProfiles = sensProf,
        verify = FALSE
      )
      
      # Plot using the constructed RadioSet
      doseResponseCurve(
        rSets=list(clevelandSmall),
        cellline=cellInfo(clevelandSmall)\$sampleid[5]
      )
    }, error = function(e) {
      message("Optional RadioSet plotting step skipped or failed: ", e\$message)
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_RADIOGX_DOSE_RESPONSE_MODELING_AND_METRICS":',
        paste0('    RadioGx: ', as.character(packageVersion('RadioGx')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dose_response_modeling_and_metrics.csv versions.yml
    """
}

workflow BIOC_RADIOGX_DOSE_RESPONSE_MODELING_AND_METRICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ radiation_doses.csv, survival_fractions.csv ] ]

    main:
    BIOC_RADIOGX_DOSE_RESPONSE_MODELING_AND_METRICS(ch_input)

    emit:
    tables   = BIOC_RADIOGX_DOSE_RESPONSE_MODELING_AND_METRICS.out.tables
    plots    = BIOC_RADIOGX_DOSE_RESPONSE_MODELING_AND_METRICS.out.plots
    objects  = BIOC_RADIOGX_DOSE_RESPONSE_MODELING_AND_METRICS.out.objects
    versions = BIOC_RADIOGX_DOSE_RESPONSE_MODELING_AND_METRICS.out.versions
}
