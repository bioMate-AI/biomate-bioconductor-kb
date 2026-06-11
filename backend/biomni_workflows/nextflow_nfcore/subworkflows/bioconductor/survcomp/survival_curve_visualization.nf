#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: survcomp — survival_curve_visualization
// Plot Kaplan-Meier survival curves for multiple datasets or stratified risk groups with risk tables.
// Input: Survival times, survival events, and group indicators
// Container: quay.io/biocontainers/bioconductor-survcomp:1.60.0--r45ha27e39d_0
// R packages: survcomp, survival
// Bioconductor: 3.20 | R: 4.4
// Requires: survcomp, survival
// Visualizations: survival plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Artificially censor survival data using censor.time
//  * 2. [Input & Preparation] Create a data frame with time, event, and group
//  * 3. [Visualization & Output] Plot Kaplan-Meier curves using km.coxph.plot

nextflow.enable.dsl = 2

process BIOC_SURVCOMP_SURVIVAL_CURVE_VISUALIZATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("survcomp", "survival")
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
    library(survcomp)
    library(survival)
    
    # Read user input
    if (!file.exists("survival_data.csv")) {
      stop("Error: 'survival_data.csv' is required but not found in the working directory.")
    }
    dd_input <- read.csv("survival_data.csv", stringsAsFactors = FALSE)
    
    # Ensure required columns exist
    required_cols <- c("time", "event", "group")
    if (!all(required_cols %in% colnames(dd_input))) {
      stop("Error: 'survival_data.csv' must contain 'time', 'event', and 'group' columns.")
    }
    
    # Define tc and myspace
    tc <- max(dd_input\$time, na.rm = TRUE)
    myspace <- " "
    
    # 1. Artificially censor survival data using censor.time
    surv.data <- censor.time(
      surv.time = dd_input\$time,
      surv.event = dd_input\$event,
      time.cens = tc
    )
    
    # 2. Create a data frame with time, event, and group
    gg <- factor(dd_input\$group)
    dd <- data.frame("time" = surv.data[[1]], "event" = surv.data[[2]], "group" = gg)
    
    # Save the processed data frame to a CSV
    write.csv(dd, "processed_survival_data.csv", row.names = FALSE)
    
    # 3. Plot Kaplan-Meier curves using km.coxph.plot
    pdf("kaplan_meier_curve.pdf", width = 8, height = 8)
    
    num_groups <- length(levels(gg))
    group_colors <- if (num_groups == 2) {
      c("darkorange", "red")
    } else {
      rainbow(num_groups)
    }
    
    # Calculate a reasonable step size for the risk table based on the time scale
    time_breaks <- pretty(dd\$time)
    step_size <- time_breaks[2] - time_breaks[1]
    
    km.coxph.plot(
      formula.s = formula(Surv(time, event) ~ group),
      data.s = dd,
      sub.s = "all",
      x.label = "Time",
      y.label = "Survival Probability",
      main.title = "",
      sub.title = "",
      leg.pos = "bottomright",
      leg.inset = 0.05,
      o.text = FALSE,
      v.line = FALSE,
      h.line = FALSE,
      .lty = rep(1, length(levels(gg))),
      show.n.risk = TRUE,
      n.risk.step = step_size,
      n.risk.cex = 0.85,
      .col = group_colors,
      leg.text = paste(levels(gg), myspace, sep = ""),
      verbose = FALSE,
      ylim = c(0, 1)
    )
    
    dev.off()

    writeLines(c(
        '"BIOC_SURVCOMP_SURVIVAL_CURVE_VISUALIZATION":',
        paste0('    survcomp: ', as.character(packageVersion('survcomp')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_survival_curve_visualization.csv versions.yml
    """
}

workflow BIOC_SURVCOMP_SURVIVAL_CURVE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Survival times, survival events, and group indicators ] ]

    main:
    BIOC_SURVCOMP_SURVIVAL_CURVE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SURVCOMP_SURVIVAL_CURVE_VISUALIZATION.out.tables
    plots    = BIOC_SURVCOMP_SURVIVAL_CURVE_VISUALIZATION.out.plots
    objects  = BIOC_SURVCOMP_SURVIVAL_CURVE_VISUALIZATION.out.objects
    versions = BIOC_SURVCOMP_SURVIVAL_CURVE_VISUALIZATION.out.versions
}
