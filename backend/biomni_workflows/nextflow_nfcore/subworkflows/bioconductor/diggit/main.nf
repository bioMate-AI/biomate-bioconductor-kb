#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: diggit — diggit_driver_inference
// Identify functional genetic drivers (CNVs) of a cellular phenotype by integrating expression, CNV, and regulatory networks.
// Input: gbmExprs, gbmCNV, gbmTFregulon, gbmMindy, gbmCNVnormal
// Container: quay.io/biocontainers/bioconductor-diggit:1.42.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biobase, diggit
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize the diggit object using diggitClass
//  * 2. [Core Analysis] Infer functional CNVs (fCNVs) associated with expression using fCNV
//  * 3. [Core Analysis] Identify Master Regulators (MRs) of the phenotype using marina
//  * 4. [Core Analysis] Map activity quantitative trait loci (aQTLs) linking fCNVs to MR activity using aqtl
//  * 5. [Core Analysis] Perform conditional association analysis using conditional to filter out passenger CNVs in linkage disequilibrium
//  * 6. [Visualization & Output] Plot and summarize the conditional analysis results using plot and summary

nextflow.enable.dsl = 2

process BIOC_DIGGIT_DIGGIT_DRIVER_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("diggit", "Biobase")
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
    library(diggit)
    library(Biobase)
    
    # Define cores for parallel processing
    cores <- 3 * (Sys.info()[1] != "Windows") + 1
    
    # Read user input files from the working directory
    gbmExprs <- readRDS("gbmExprs.rds")
    gbmCNV <- readRDS("gbmCNV.rds")
    gbmTFregulon <- readRDS("gbmTFregulon.rds")
    gbmMindy <- readRDS("gbmMindy.rds")
    gbmCNVnormal <- readRDS("gbmCNVnormal.rds")
    
    # Subset genes to match the documented workflow
    genes <- intersect(rownames(gbmExprs), rownames(gbmCNV))[1:1000]
    gbmCNV <- gbmCNV[match(genes, rownames(gbmCNV)), ]
    
    # Initialize the diggit object
    dobj <- diggitClass(expset=gbmExprs, cnv=gbmCNV, regulon=gbmTFregulon, mindy=gbmMindy)
    
    # Infer functional CNVs (fCNVs) using Spearman correlation
    dobj <- fCNV(dobj, method="spearman", verbose=FALSE)
    
    # Set random seed for reproducible mutual information (MI) permutation analysis
    RNGkind("L'Ecuyer-CMRG")
    set.seed(1)
    
    # Infer functional CNVs (fCNVs) using Mutual Information
    dobj <- fCNV(dobj, method="mi", cores=cores, verbose=FALSE)
    
    # Identify Master Regulators (MRs) of the phenotype
    dobj <- marina(dobj, pheno="subtype", group1="MES", group2="PN", cores=cores, verbose=FALSE)
    
    # Map activity quantitative trait loci (aQTLs) linking fCNVs to MR activity
    dobj <- aqtl(dobj, mr=c("CEBPD", "STAT3"), method="mi", cores=cores, verbose=FALSE)
    
    # Calculate CNV threshold from normal samples
    cnvthr <- quantile(as.vector(gbmCNVnormal), c(.025, .975), na.rm=TRUE)
    
    # Perform conditional association analysis to filter out passenger CNVs
    dobj <- conditional(dobj, pheno="subtype", group1="MES", group2="PN", mr="STAT3", cnv=cnvthr, cores=cores, verbose=FALSE)
    
    # Plot and save the conditional analysis results
    pdf("conditional_association_plot.pdf", width=8, height=6)
    plot(dobj, "STAT3", cluster="2")
    dev.off()
    
    # Summarize and save the standard conditional analysis results
    sum_standard <- summary(dobj)
    if (is.list(sum_standard)) {
      for (name in names(sum_standard)) {
        write.csv(as.data.frame(sum_standard[[name]]), file=paste0("summary_conditional_standard_", name, ".csv"), row.names=TRUE)
      }
    } else {
      write.csv(as.data.frame(sum_standard), file="summary_conditional_standard.csv", row.names=TRUE)
    }
    
    # Perform aQTL analysis restricted to upstream post-translational modulators (MINDy)
    dobj <- aqtl(dobj, mr=c("CEBPD", "STAT3"), method="mi", mindy=TRUE, cores=cores, verbose=FALSE)
    
    # Perform conditional association analysis with the MINDy-restricted aQTLs
    dobj <- conditional(dobj, pheno="subtype", group1="MES", group2="PN", mr="STAT3", cnv=cnvthr, verbose=FALSE)
    
    # Summarize and save the MINDy-restricted conditional analysis results
    sum_mindy <- summary(dobj)
    if (is.list(sum_mindy)) {
      for (name in names(sum_mindy)) {
        write.csv(as.data.frame(sum_mindy[[name]]), file=paste0("summary_conditional_mindy_", name, ".csv"), row.names=TRUE)
      }
    } else {
      write.csv(as.data.frame(sum_mindy), file="summary_conditional_mindy.csv", row.names=TRUE)
    }
    
    # Save the final diggit object
    saveRDS(dobj, file="diggit_final_object.rds")

    writeLines(c(
        '"BIOC_DIGGIT_DIGGIT_DRIVER_INFERENCE":',
        paste0('    diggit: ', as.character(packageVersion('diggit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_diggit_driver_inference.csv versions.yml
    """
}

workflow BIOC_DIGGIT_DIGGIT_DRIVER_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gbmExprs, gbmCNV, gbmTFregulon, gbmMindy, gbmCNVnormal ] ]

    main:
    BIOC_DIGGIT_DIGGIT_DRIVER_INFERENCE(ch_input)

    emit:
    tables   = BIOC_DIGGIT_DIGGIT_DRIVER_INFERENCE.out.tables
    plots    = BIOC_DIGGIT_DIGGIT_DRIVER_INFERENCE.out.plots
    objects  = BIOC_DIGGIT_DIGGIT_DRIVER_INFERENCE.out.objects
    versions = BIOC_DIGGIT_DIGGIT_DRIVER_INFERENCE.out.versions
}
