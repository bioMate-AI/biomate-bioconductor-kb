#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: omicRexposome — association_study
// Perform association testing between exposome data and a single omic dataset (e.g., transcriptome or proteome) using a limma-based pipeline with optional SVA adj
// Input: brge_expo, brge_gexp, brge_prot
// Container: quay.io/biocontainers/bioconductor-omicrexposome:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MultiDataSet, ggplot2, gridExtra, omicRexposome
// Visualizations: volcano plot
// QC: batch-effect correction
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load exposome and omic datasets
//  * 2. [Input & Preparation] Create a MultiDataSet object and add both datasets using createMultiDataSet(), add_genexp() (or add_eset()), and add_exp()
//  * 3. [Core Analysis] Run association analysis using association()
//  * 4. [Core Analysis] Evaluate results using tableHits() and tableLambda()
//  * 5. [Core Analysis] Re-run association with SVA adjustment (sva = "fast") if lambda scores indicate inflation/deflation
//  * 6. [Visualization & Output] Visualize associations using plotAssociation() (QQ plots, volcano plots, or protein plots)

nextflow.enable.dsl = 2

process BIOC_OMICREXPOSOME_ASSOCIATION_STUDY {
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
    .bm_deps <- c("omicRexposome", "MultiDataSet", "ggplot2", "gridExtra")
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
    library(omicRexposome)
    library(MultiDataSet)
    library(ggplot2)
    library(gridExtra)
    
    # Helper function to load input files robustly
    load_input <- function(filename) {
      if (file.exists(filename)) {
        return(readRDS(filename))
      } else if (file.exists(paste0(filename, ".rds"))) {
        return(readRDS(paste0(filename, ".rds")))
      } else {
        stop(paste("Required input file not found:", filename))
      }
    }
    
    # 1. Load exposome and omic datasets from the working directory
    brge_expo <- load_input("brge_expo")
    brge_gexp <- load_input("brge_gexp")
    brge_prot <- load_input("brge_prot")
    
    # 2. Create a MultiDataSet object and add both datasets
    mds <- createMultiDataSet()
    mds <- add_genexp(mds, brge_gexp)
    mds <- add_exp(mds, brge_expo)
    
    # 3. Run association analysis (without SVA)
    # Fixed Bug 1: Removed hardcoded covariates (~Sex+Age) to prevent failure on datasets without them
    gexp <- association(mds, formula=~1, expset = "exposures", omicset = "expression")
    
    # 4. Evaluate results
    hit <- tableHits(gexp, th=0.001)
    lab <- tableLambda(gexp)
    res_no_sva <- merge(hit, lab, by="exposure")
    
    # Save intermediate results
    write.csv(res_no_sva, "gexp_hits_no_sva.csv", row.names=FALSE)
    saveRDS(gexp, "gexp_association_no_sva.rds")
    
    # 5. Re-run association with SVA adjustment (sva = "fast")
    gexp <- association(mds, formula=~1, expset = "exposures", omicset = "expression", sva = "fast")
    hit <- tableHits(gexp, th=0.001)
    lab <- tableLambda(gexp)
    res_sva <- merge(hit, lab, by="exposure")
    
    # Save SVA results
    write.csv(res_sva, "gexp_hits_sva.csv", row.names=FALSE)
    saveRDS(gexp, "gexp_association_sva.rds")
    
    # Fixed Bug 2: Dynamically extract exposure names to avoid hardcoded names that might not exist
    expo_names <- as.character(res_sva\$exposure)
    expo1 <- expo_names[1]
    expo2 <- ifelse(length(expo_names) > 1, expo_names[2], expo_names[1])
    
    # 6. Visualize associations (QQ plots and Volcano plots)
    pdf("gexp_qq_plots.pdf", width=10, height=5)
    gridExtra::grid.arrange(
        plotAssociation(gexp, rid=expo1, type="qq") + 
            ggplot2::ggtitle(paste("Transcriptome -", expo1, "Association")),
        plotAssociation(gexp, rid=expo2, type="qq") + 
            ggplot2::ggtitle(paste("Transcriptome -", expo2, "Association")),
        ncol=2
    )
    dev.off()
    
    pdf("gexp_volcano_plots.pdf", width=10, height=5)
    gridExtra::grid.arrange(
        plotAssociation(gexp, rid=expo1, type="volcano", tPV=-log10(1e-04)) + 
            ggplot2::ggtitle(paste("Transcriptome -", expo1, "Association")),
        plotAssociation(gexp, rid=expo2, type="volcano", tPV=-log10(1e-04)) + 
            ggplot2::ggtitle(paste("Transcriptome -", expo2, "Association")),
        ncol=2
    )
    dev.off()
    
    # 7. Exposome - Proteome Data Association
    mds <- createMultiDataSet()
    mds <- add_eset(mds, brge_prot, dataset.type  ="proteome")
    mds <- add_exp(mds, brge_expo)
    
    prot <- association(mds, formula=~1, expset = "exposures", omicset = "proteome")
    prot_hits <- tableHits(prot, th=0.001)
    
    # Save proteome results
    write.csv(prot_hits, "prot_hits.csv", row.names=TRUE)
    saveRDS(prot, "prot_association.rds")
    
    # Visualize proteome associations
    pdf("prot_plots.pdf", width=10, height=5)
    gridExtra::grid.arrange(
        plotAssociation(prot, rid=expo1, type="protein") + 
            ggplot2::ggtitle(paste("Proteome -", expo1, "Association")) +
            ggplot2::geom_hline(yintercept = 1, color = "LightPink"),
        plotAssociation(prot, rid=expo2, type="protein") + 
            ggplot2::ggtitle(paste("Proteome -", expo2, "Association")) +
            ggplot2::geom_hline(yintercept = 1, color = "LightPink"),
        ncol=2
    )
    dev.off()

    writeLines(c(
        '"BIOC_OMICREXPOSOME_ASSOCIATION_STUDY":',
        paste0('    omicRexposome: ', as.character(packageVersion('omicRexposome')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_association_study.csv versions.yml
    """
}

workflow BIOC_OMICREXPOSOME_ASSOCIATION_STUDY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ brge_expo, brge_gexp, brge_prot ] ]

    main:
    BIOC_OMICREXPOSOME_ASSOCIATION_STUDY(ch_input)

    emit:
    tables   = BIOC_OMICREXPOSOME_ASSOCIATION_STUDY.out.tables
    plots    = BIOC_OMICREXPOSOME_ASSOCIATION_STUDY.out.plots
    objects  = BIOC_OMICREXPOSOME_ASSOCIATION_STUDY.out.objects
    versions = BIOC_OMICREXPOSOME_ASSOCIATION_STUDY.out.versions
}
