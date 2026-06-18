#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowTime — custom_yeast_gating
// Create and save custom gating schemes (yeast population and singlet gates) from a flowSet.
// Input: .fcs files, .csv file
// Container: quay.io/biocontainers/bioconductor-flowtime:1.34.0--r45hdfd78af_0
// R packages: flowClust, flowCore, flowStats, flowTime, ggcyto, openCyto
// Bioconductor: 3.20 | R: 4.4
// Requires: flowClust, flowCore, flowStats, flowTime, ggcyto, openCyto
// Visualizations: autoplot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Import and annotate flowSet using read.flowSet and annotateFlowSet
//  * 2. [Core Analysis] Combine flowSet into a single frame for gate definition using fsApply
//  * 3. [Core Analysis] Estimate and apply logicle transformation using estimateLogicle and transform
//  * 4. [Input & Preparation] Define yeast population gate using gate_flowClust_2d
//  * 5. [Core Analysis] Reverse transform the gate and data using inverseLogicleTransform
//  * 6. [Input & Preparation] Define singlet gate using gate_singlet
//  * 7. [Visualization & Output] Save custom gates using saveGates

nextflow.enable.dsl = 2

process BIOC_FLOWTIME_CUSTOM_YEAST_GATING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20-slim"

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
    .bm_deps <- c("flowClust", "flowCore", "flowStats", "flowTime", "ggcyto", "openCyto")
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
    
    # Load required libraries
    library(flowCore)
    library(flowTime)
    library(openCyto)
    library(ggcyto)
    library(flowClust)
    library(flowStats)
    
    # ==========================================
    # 1. Import and annotate flowSet
    # ==========================================
    
    # Find FCS files in the working directory
    fcs_files <- list.files(path = ".", pattern = "\\\\.fcs\$", full.names = TRUE)
    if (length(fcs_files) == 0) {
      stop("Error: No .fcs files found in the working directory.")
    }
    
    # Read the flowSet from the current directory
    data <- read.flowSet(path = ".", pattern = "\\\\.fcs\$", alter.names = TRUE)
    
    # Find the CSV annotation file in the working directory
    csv_files <- list.files(path = ".", pattern = "\\\\.csv\$", full.names = TRUE)
    if (length(csv_files) == 0) {
      stop("Error: No .csv annotation file found in the working directory.")
    }
    
    annotation <- read.csv(csv_files[1])
    
    # Annotate the flowSet using the exact documented function and arguments
    adat <- annotateFlowSet(yourFlowSet = data, annotation_df = annotation, mergeBy = "name")
    
    # Save the annotated flowSet as an RDS object
    saveRDS(adat, file = "annotated_flowSet.rds")
    
    # ==========================================
    # 2. Combine flowSet into a single frame
    # ==========================================
    data.1frame <- data[[1]]
    exprs(data.1frame) <- fsApply(data, function(x) {
      x <- exprs(x)
      return(x)
    })
    
    # ==========================================
    # 3. Estimate and apply logicle transformation
    # ==========================================
    chnls <- c("FSC.A", "SSC.A", "FSC.H", "SSC.H")
    trans <- estimateLogicle(data.1frame, channels = chnls)
    inv.trans <- inverseLogicleTransform(trans)
    data.1frame <- transform(data.1frame, trans)
    
    # ==========================================
    # 4. Define yeast population gate
    # ==========================================
    yeast <- gate_flowClust_2d(data.1frame, xChannel = "FSC.A", yChannel = "SSC.A", K = 1, quantile = 0.95, min = c(0, 0))
    
    # ==========================================
    # 5. Reverse transform the gate and data
    # ==========================================
    yeast <- transform(yeast, inv.trans)
    data.1frame <- transform(data.1frame, inv.trans)
    
    # ==========================================
    # 6. Define singlet gate
    # ==========================================
    singlets <- gate_singlet(x = Subset(data.1frame, yeast), area = "FSC.A", height = "FSC.H", prediction_level = 0.999, maxit = 20)
    
    # ==========================================
    # 7. Save custom gates
    # ==========================================
    saveGates(yeastGate = yeast, dipsingletGate = singlets, fileName = "PSB_Accuri_W303.RData")
    
    # ==========================================
    # 8. Generate Diagnostic Plots
    # ==========================================
    pdf("custom_gating_plots.pdf", width = 11, height = 8.5)
    tryCatch({
      p1 <- autoplot(data.1frame, x = "FSC.A", y = "SSC.A") + geom_gate(yeast) + ggtitle("Yeast Population Gate")
      p2 <- autoplot(Subset(data.1frame, yeast), x = "FSC.A", y = "FSC.H") + geom_gate(singlets) + ggtitle("Singlets Gate")
      print(p1)
      print(p2)
    }, error = function(e) {
      warning("Could not generate diagnostic plots: ", e\$message)
    })
    dev.off()

    writeLines(c(
        '"BIOC_FLOWTIME_CUSTOM_YEAST_GATING":',
        paste0('    flowTime: ', as.character(packageVersion('flowTime')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_yeast_gating.csv versions.yml
    """
}

workflow BIOC_FLOWTIME_CUSTOM_YEAST_GATING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ .fcs files, .csv file ] ]

    main:
    BIOC_FLOWTIME_CUSTOM_YEAST_GATING(ch_input)

    emit:
    tables   = BIOC_FLOWTIME_CUSTOM_YEAST_GATING.out.tables
    plots    = BIOC_FLOWTIME_CUSTOM_YEAST_GATING.out.plots
    objects  = BIOC_FLOWTIME_CUSTOM_YEAST_GATING.out.objects
    versions = BIOC_FLOWTIME_CUSTOM_YEAST_GATING.out.versions
}
