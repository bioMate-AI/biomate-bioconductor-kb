#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: opencyto — automated_template_gating
// Perform automated hierarchical gating on raw FCS files using a predefined CSV gating template.
// Input: fcsFiles, gtFile
// Container: quay.io/biocontainers/bioconductor-opencyto:2.22.0--r45ha27e39d_0
// R packages: CytoML, flowCore, flowWorkspace, flowworkspacedata, ggcyto, openCyto
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OPENCYTO_AUTOMATED_TEMPLATE_GATING {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-opencyto:2.22.0--r45ha27e39d_0"

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
    .bm_deps <- c("CytoML", "flowCore", "flowWorkspace", "flowworkspacedata", "ggcyto", "openCyto")
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
    library(openCyto)
    library(flowWorkspace)
    library(flowCore)
    library(ggcyto)
    
    # --- Load raw FCS files into a cytoset and initialize a ---
    flowDataPath <- "."
    fcsFiles <- list.files(pattern = "CytoTrol", flowDataPath, full = TRUE)
    if (length(fcsFiles) == 0) {
      fcsFiles <- list.files(pattern = "\\\\.fcs\$", path = flowDataPath, full = TRUE, ignore.case = TRUE)
    }
    if (length(fcsFiles) == 0) {
      stop("No FCS files found in the working directory.")
    }
    
    cs  <- load_cytoset_from_fcs(fcsFiles)
    cf <- realize_view(cs[[1]])
    gs <- GatingSet(cs)
    
    # --- Apply compensation using a compensation matrix ---
    gh <- gs[[1]]
    compMat <- gh_get_compensations(gh)
    
    # Robust fallback if compMat is NULL or invalid
    if (is.null(compMat) || (is.character(compMat) && compMat == "No compensation")) {
      # Try to extract spillover from the cytoframe
      fr <- cytoframe_to_flowFrame(cf)
      spill <- flowCore::spillover(fr)
      spill_mat <- NULL
      for (name in names(spill)) {
        if (is.matrix(spill[[name]])) {
          spill_mat <- spill[[name]]
          break
        }
      }
      if (is.null(spill_mat) && !is.null(attr(fr, "description")\$SPILL)) {
        spill_mat <- attr(fr, "description")\$SPILL
      }
      if (is.null(spill_mat)) {
        # Create identity matrix for marker channels
        chnls_all <- colnames(fr)
        marker_chnls <- chnls_all[!grepl("FSC|SSC|Time", chnls_all, ignore.case = TRUE)]
        spill_mat <- diag(length(marker_chnls))
        colnames(spill_mat) <- marker_chnls
        rownames(spill_mat) <- marker_chnls
      }
      compMat <- compensation(spill_mat)
    }
    
    compensate(gs, compMat)
    
    # --- Transform the stained channels ---
    chnls <- parameters(compMat)
    trans <- estimateLogicle(gs[[1]], channels = chnls)
    gs <- transform(gs, trans)
    
    # --- Load the gating template from the CSV file ---
    gtFile <- list.files(pattern = "\\\\.csv\$", full.names = TRUE)[1]
    if (is.na(gtFile)) {
      stop("No CSV gating template found in the working directory.")
    }
    gt_tcell <- gatingTemplate(gtFile)
    
    # --- Apply the gating template to the GatingSet using gt_gating ---
    gt_gating(gt_tcell, gs)
    
    # --- Hide intermediate or auxiliary gating nodes and rename ---
    all_paths <- gs_get_pop_paths(gs[[1]])
    nodesToHide_vignette <- c("cd8+", "cd4+", "cd4-cd8-", "cd4+cd8+", "cd4+cd8-/HLA+", "cd4+cd8-/CD38+",
                              "cd4-cd8+/HLA+", "cd4-cd8+/CD38+", "CD45_neg/CCR7_gate", "cd4+cd8-/CD45_neg",
                              "cd4-cd8+/CCR7+", "cd4-cd8+/CD45RA+")
    # Filter to only those that exist to avoid runtime errors
    nodesToHide <- nodesToHide_vignette[nodesToHide_vignette %in% all_paths]
    
    tryCatch({
      lapply(nodesToHide, function(thisNode) gs_pop_set_visibility(gs, thisNode, FALSE))
    }, error = function(e) {
      warning("Could not hide nodes: ", e\$message)
    })
    
    tryCatch({
      gs_pop_set_name(gs, "cd4+cd8-", "cd4")
    }, error = function(e) {
      message("Skipping renaming of cd4+cd8- (not found or already renamed)")
    })
    
    tryCatch({
      gs_pop_set_name(gs, "cd4-cd8+", "cd8")
    }, error = function(e) {
      message("Skipping renaming of cd4-cd8+ (not found or already renamed)")
    })
    
    # --- Plot the gating hierarchy and visualize the gates ---
    pdf("gating_plots.pdf", width = 11, height = 8.5)
    tryCatch({
      plot(gs[[1]])
    }, error = function(e) {
      warning("plot(gs[[1]]) failed: ", e\$message)
    })
    
    tryCatch({
      print(autoplot(gs[[1]]))
    }, error = function(e) {
      warning("autoplot(gs[[1]]) failed: ", e\$message)
    })
    dev.off()
    
    # Save GatingSet and population statistics
    suppressWarnings(dir.create("gating_set_output", showWarnings = FALSE))
    save_gs(gs, path = "gating_set_output/gs_auto")
    
    stats <- gs_pop_get_count_fast(gs)
    write.csv(stats, "population_counts.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to 'gating_plots.pdf', 'population_counts.csv', and 'gating_set_output/'.")

    writeLines(c(
        '"BIOC_OPENCYTO_AUTOMATED_TEMPLATE_GATING":',
        paste0('        opencyto: ', as.character(packageVersion("opencyto")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_template_gating.csv versions.yml
    """
}

workflow BIOC_OPENCYTO_AUTOMATED_TEMPLATE_GATING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ fcsFiles, gtFile ] ]

    main:
    BIOC_OPENCYTO_AUTOMATED_TEMPLATE_GATING(ch_input)

    emit:
    tables   = BIOC_OPENCYTO_AUTOMATED_TEMPLATE_GATING.out.tables
    plots    = BIOC_OPENCYTO_AUTOMATED_TEMPLATE_GATING.out.plots
    objects  = BIOC_OPENCYTO_AUTOMATED_TEMPLATE_GATING.out.objects
    versions = BIOC_OPENCYTO_AUTOMATED_TEMPLATE_GATING.out.versions
}
