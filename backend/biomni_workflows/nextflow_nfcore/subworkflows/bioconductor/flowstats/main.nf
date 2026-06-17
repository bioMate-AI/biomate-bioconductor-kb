#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: flowStats — automated_gating_and_normalization
// Perform automated gating and landmark-based normalization on a GatingSet of flow cytometry data.
// Input: ITN
// Container: quay.io/biocontainers/bioconductor-flowstats:4.22.0--r45hdfd78af_0
// R packages: flowCore, flowStats, flowWorkspace, ggcyto, ggridges, gridExtra, scales
// Bioconductor: 3.20 | R: 4.4
// Requires: flowCore, flowStats, flowWorkspace, ggcyto, scales
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and transform fluorescence channels using GatingSet and transformerList
//  * 2. [Core Analysis] Identify T-cells using lymphGate and add to the GatingSet
//  * 3. [Core Analysis] Estimate quadrant gates using quadrantGate
//  * 4. [Core Analysis] Normalize CD4 and CD8 channels across samples using normalize
//  * 5. [Core Analysis] Identify activated T-helper cells using rangeGate and normalize the CD69 channel

nextflow.enable.dsl = 2

process BIOC_FLOWSTATS_AUTOMATED_GATING_AND_NORMALIZATION {
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
    .bm_deps <- c("flowCore", "flowStats", "flowWorkspace", "ggcyto", "ggridges", "gridExtra", "scales")
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
        
    library(flowCore)
    library(flowStats)
    library(flowWorkspace)
    library(ggcyto)
    library(scales)
    
    # Read user input (ITN flowSet saved as an RDS file in the working directory)
    ITN <- readRDS("ITN")
    
    # 1. Load data and transform fluorescence channels using GatingSet and transformerList
    if (inherits(ITN, "GatingSet")) {
      gs <- ITN
    } else {
      gs <- GatingSet(ITN)
    }
    
    trans.func <- asinh
    inv.func <- sinh
    trans.obj <- trans_new("myAsinh", trans.func, inv.func)
    
    # Dynamically identify fluorescence channels (exclude FSC, SSC, and Time)
    cols <- colnames(gs)
    fluor_cols <- cols[!grepl("FSC|SSC|Time", cols, ignore.case = TRUE)]
    transList <- transformerList(fluor_cols, trans.obj)
    gs <- transform(gs, transList)
    
    # 2. Identify T-cells using lymphGate and add to the GatingSet
    lg <- lymphGate(gs_cyto_data(gs), channels=c("CD3", "SSC"),
                    preselection="CD4", filterId="TCells",
                    scale=2.5)
    gs_pop_add(gs, lg)
    recompute(gs)
    
    # 3. Estimate quadrant gates using quadrantGate
    qgate <- quadrantGate(gs_pop_get_data(gs, "TCells"), stains=c("CD4", "CD8"),
                          filterId="CD4CD8", sd=3)
    gs_pop_add(gs, qgate, parent = "TCells")
    recompute(gs)
    
    # 4. Normalize CD4 and CD8 channels across samples using normalize
    gs <- normalize(gs, populations=c("CD4+CD8+", "CD4+CD8-", "CD4-CD8+", "CD4-CD8-"), 
                         dims=c("CD4", "CD8"), minCountThreshold = 50)
    
    # 5. Identify activated T-helper cells using rangeGate and normalize the CD69 channel
    CD69rg <- rangeGate(gs_cyto_data(gs), stain="CD69",
                        alpha=0.75, filterId="CD4+CD8-CD69", sd=2.5)
    gs_pop_add(gs, CD69rg, parent="CD4+CD8-")
    recompute(gs)
    gs <- normalize(gs, populations=c("CD4+CD8-CD69"), 
                         dims=c("CD69"), minCountThreshold = 50)
    
    # Save the final GatingSet
    save_gs(gs, path = "gs_normalized")
    
    # Export population statistics
    stats <- gs_pop_get_stats(gs)
    write.csv(stats, "population_statistics.csv", row.names = FALSE)
    
    # Generate diagnostic plots
    pdf("gating_and_normalization_plots.pdf", width = 11, height = 8.5)
    
    # Plot TCells gate
    p1 <- ggcyto(gs, aes(x = CD3, y = SSC)) + 
      geom_hex(bins = 32) + 
      geom_gate("TCells") +
      ggtitle("T-Cell Gating (lymphGate)")
    print(p1)
    
    # Plot CD4 vs CD8 quadrant gates after normalization
    p2 <- ggcyto(gs_pop_get_data(gs, "TCells"), aes(x=CD4, y=CD8)) +
      geom_hex(bins=32) +
      geom_gate(gs_pop_get_gate(gs, "CD4-CD8-")) +
      geom_gate(gs_pop_get_gate(gs, "CD4-CD8+")) +
      geom_gate(gs_pop_get_gate(gs, "CD4+CD8-")) +
      geom_gate(gs_pop_get_gate(gs, "CD4+CD8+")) +
      ggtitle("CD4 vs CD8 Gating (quadrantGate)")
    print(p2)
    
    # Plot CD69 range gate
    p3 <- ggcyto(gs_pop_get_data(gs, "CD4+CD8-"), aes(x=CD69)) +
      geom_density(alpha = 0.4, fill = "blue") +
      geom_vline(xintercept = CD69rg@min, linetype = "dashed", color = "red") +
      ggtitle("CD69 Activation Gating (rangeGate)")
    print(p3)
    
    dev.off()

    writeLines(c(
        '"BIOC_FLOWSTATS_AUTOMATED_GATING_AND_NORMALIZATION":',
        paste0('    flowStats: ', as.character(packageVersion('flowStats')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_automated_gating_and_normalization.csv versions.yml
    """
}

workflow BIOC_FLOWSTATS_AUTOMATED_GATING_AND_NORMALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ITN ] ]

    main:
    BIOC_FLOWSTATS_AUTOMATED_GATING_AND_NORMALIZATION(ch_input)

    emit:
    tables   = BIOC_FLOWSTATS_AUTOMATED_GATING_AND_NORMALIZATION.out.tables
    plots    = BIOC_FLOWSTATS_AUTOMATED_GATING_AND_NORMALIZATION.out.plots
    objects  = BIOC_FLOWSTATS_AUTOMATED_GATING_AND_NORMALIZATION.out.objects
    versions = BIOC_FLOWSTATS_AUTOMATED_GATING_AND_NORMALIZATION.out.versions
}
