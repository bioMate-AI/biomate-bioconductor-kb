#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylKit — base_resolution_diff_meth
// Perform base-resolution differential methylation analysis, sample comparative analysis, and genomic annotation using in-memory objects.
// Input: file.list, gene.obj, cpg.obj
// Container: quay.io/biocontainers/bioconductor-methylkit:1.36.0--r45ha27e39d_0
// R packages: genomation, methylKit
// Bioconductor: 3.20 | R: 4.4
// Requires: genomation, methylKit
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read methylation call files
//  * 2. [Core Analysis] Filter samples by coverage
//  * 3. [Core Analysis] Merge samples to find common covered bases
//  * 4. [Core Analysis] Calculate sample correlation and perform clustering/PCA
//  * 5. [Core Analysis] Calculate differential methylation
//  * 6. [Core Analysis] Extract hyper/hypo-methylated bases
//  * 7. [Core Analysis] Annotate differentially methylated bases with genic parts and CpG features

nextflow.enable.dsl = 2

process BIOC_METHYLKIT_BASE_RESOLUTION_DIFF_METH {
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
    .bm_deps <- c("genomation", "methylKit")
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
        
        # Load required Bioconductor libraries
        library(methylKit)
        library(genomation)
        
        # 1. Read methylation call files and annotation files from the working directory
        # Read the list of file paths from the "file.list" text file
        file.list <- readLines("file.list")
        
        # Read the transcript features from the "gene.obj" BED file
        gene.obj <- readTranscriptFeatures("gene.obj")
        
        # Read the CpG features from the "cpg.obj" BED file
        cpg.obj <- readFeatureFlank("cpg.obj", feature.flank.name = c("CpGi", "shores"))
        
        n_files <- length(file.list)
        my_sample_ids <- as.list(paste0("sample", seq_len(n_files)))
        my_treatment <- c(rep(1, ceiling(n_files/2)), rep(0, floor(n_files/2)))
        
        # Read the methylation files into a methylRawList object
        myobj=methRead(as.list(file.list),
                   sample.id=my_sample_ids,
                   assembly="hg18",
                   treatment=my_treatment,
                   context="CpG",
                   mincov = 10
                   )
        
        # 2. Filter samples by coverage
        filtered.myobj=filterByCoverage(myobj,lo.count=10,lo.perc=NULL,
                                              hi.count=NULL,hi.perc=99.9)
        
        # 3. Merge samples to find common covered bases
        meth=unite(filtered.myobj, destrand=FALSE)
        
        # 4. Calculate sample correlation and perform clustering/PCA
        # Save comparative analysis plots to a PDF file
        pdf("sample_comparative_analysis.pdf", width = 8, height = 8)
        getCorrelation(meth,plot=TRUE)
        clusterSamples(meth, dist="correlation", method="ward", plot=TRUE)
        PCASamples(meth)
        dev.off()
        
        # 5. Calculate differential methylation
        myDiff=calculateDiffMeth(meth)
        
        # 6. Extract hyper/hypo-methylated bases
        myDiff25p=getMethylDiff(myDiff,difference=25,qvalue=0.01)
        
        # Save differential methylation results to files
        write.csv(as.data.frame(myDiff), "differential_methylation_all.csv", row.names = FALSE)
        write.csv(as.data.frame(myDiff25p), "differential_methylation_q0.01_diff25.csv", row.names = FALSE)
        saveRDS(myDiff, "myDiff.rds")
        saveRDS(myDiff25p, "myDiff25p.rds")
        
        # 7. Annotate differentially methylated bases with genic parts and CpG features
        gene_ann <- annotateWithGeneParts(as(myDiff25p,"GRanges"),gene.obj)
        diffCpGann=annotateWithFeatureFlank(as(myDiff25p,"GRanges"),
                                            cpg.obj\$CpGi,cpg.obj\$shores,
                                 feature.name="CpGi",flank.name="shores")
        
        # Save annotation objects
        saveRDS(gene_ann, "gene_annotation.rds")
        saveRDS(diffCpGann, "cpg_annotation.rds")
        
        # Save annotation visualization plots
        pdf("differential_methylation_annotation_plots.pdf", width = 8, height = 8)
        plotTargetAnnotation(gene_ann, precedence = TRUE, main = "Differential Methylation Genic Annotation")
        plotTargetAnnotation(diffCpGann, col = c("green", "gray", "white"), main = "Differential Methylation CpG Annotation")
        dev.off()

    writeLines(c(
        '"BIOC_METHYLKIT_BASE_RESOLUTION_DIFF_METH":',
        paste0('    methylKit: ', as.character(packageVersion('methylKit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_base_resolution_diff_meth.csv versions.yml
    """
}

workflow BIOC_METHYLKIT_BASE_RESOLUTION_DIFF_METH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.list, gene.obj, cpg.obj ] ]

    main:
    BIOC_METHYLKIT_BASE_RESOLUTION_DIFF_METH(ch_input)

    emit:
    tables   = BIOC_METHYLKIT_BASE_RESOLUTION_DIFF_METH.out.tables
    plots    = BIOC_METHYLKIT_BASE_RESOLUTION_DIFF_METH.out.plots
    objects  = BIOC_METHYLKIT_BASE_RESOLUTION_DIFF_METH.out.objects
    versions = BIOC_METHYLKIT_BASE_RESOLUTION_DIFF_METH.out.versions
}
