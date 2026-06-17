#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribosomeProfilingQC — rpf_only_differential_analysis
// Generate count matrices for RPFs and perform differential translation analysis using edgeR.
// Input: RPF.WT.1.bam, RPF.WT.2.bam, RPF.KD1.1.bam, RPF.KD1.2.bam, Danio_rerio.GRCz10.91.chr1.gtf.gz
// Container: quay.io/biocontainers/bioconductor-ribosomeprofilingqc:1.22.0--r45hdfd78af_0
// R packages: AnnotationDbi, edgeR, ribosomeProfilingQC
// Bioconductor: 3.20 | R: 4.4
// Requires: AnnotationDbi, edgeR, ribosomeProfilingQC
// QC: TMM normalization, dispersion/size-factor estimation
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Count reads across samples at the gene level
//  * 2. [Core Analysis] Perform differential analysis using edgeR

nextflow.enable.dsl = 2

process BIOC_RIBOSOMEPROFILINGQC_RPF_ONLY_DIFFERENTIAL_ANALYSIS {
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
    .bm_deps <- c("AnnotationDbi", "edgeR", "ribosomeProfilingQC")
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
        library(ribosomeProfilingQC)
        library(AnnotationDbi)
        library(edgeR)
        
        # Define input files from the working directory as specified by the user
        RPFs <- c("RPF.KD1.1.bam", "RPF.KD1.2.bam", "RPF.WT.1.bam", "RPF.WT.2.bam")
        gtf <- "Danio_rerio.GRCz10.91.chr1.gtf.gz"
        
        # Verify that all required input files exist in the working directory
        for (f in c(RPFs, gtf)) {
          if (!file.exists(f)) {
            stop(paste("Required input file missing in the working directory:", f))
          }
        }
        
        # 1. Count reads across samples at the gene level
        cnts <- countReads(RPFs, gtf=gtf, level="gene",
                           bestpsite=13, readsLen=c(28,29))
        
        # Print the head of the counts matrix to console
        print("RPF Counts (First 6 rows):")
        print(head(cnts\$RPFs))
        
        # Save the counts matrix and the full counts object
        write.csv(cbind(cnts\$annotation[rownames(cnts\$RPFs), ], cnts\$RPFs), 
                  "rpf_gene_counts.csv", row.names=TRUE)
        saveRDS(cnts, "cnts.rds")
        
        # 2. Perform differential analysis using edgeR
        gp <- c("KD", "KD", "CTL", "CTL")
        y <- DGEList(counts = cnts\$RPFs, group = gp)
        y <- calcNormFactors(y)
        design <- model.matrix(~0+gp)
        colnames(design) <- sub("gp", "", colnames(design))
        y <- estimateDisp(y, design)
        
        # Define contrast for KD vs CTL
        my.contrast <- makeContrasts(KD - CTL, levels=design)
        
        # Perform quasi-likelihood F-tests
        fit <- glmQLFit(y, design)
        qlf <- glmQLFTest(fit, contrast=my.contrast)
        print("Top 3 tags from Quasi-Likelihood F-test:")
        print(topTags(qlf, n=3))
        
        # Save all QLF results to CSV
        qlf_all <- topTags(qlf, n=nrow(qlf))
        write.csv(as.data.frame(qlf_all), "edgeR_qlf_results.csv", row.names=TRUE)
        
        # Perform likelihood ratio tests
        fit <- glmFit(y, design)
        lrt <- glmLRT(fit, contrast=my.contrast)
        print("Top 3 tags from Likelihood Ratio test:")
        print(topTags(lrt, n=3))
        
        # Save all LRT results to CSV
        lrt_all <- topTags(lrt, n=nrow(lrt))
        write.csv(as.data.frame(lrt_all), "edgeR_lrt_results.csv", row.names=TRUE)

    writeLines(c(
        '"BIOC_RIBOSOMEPROFILINGQC_RPF_ONLY_DIFFERENTIAL_ANALYSIS":',
        paste0('    ribosomeProfilingQC: ', as.character(packageVersion('ribosomeProfilingQC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rpf_only_differential_analysis.csv versions.yml
    """
}

workflow BIOC_RIBOSOMEPROFILINGQC_RPF_ONLY_DIFFERENTIAL_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ RPF.WT.1.bam, RPF.WT.2.bam, RPF.KD1.1.bam, RPF.KD1.2.bam, Danio_rerio.GRCz10.91.chr1.gtf.gz ] ]

    main:
    BIOC_RIBOSOMEPROFILINGQC_RPF_ONLY_DIFFERENTIAL_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RIBOSOMEPROFILINGQC_RPF_ONLY_DIFFERENTIAL_ANALYSIS.out.tables
    plots    = BIOC_RIBOSOMEPROFILINGQC_RPF_ONLY_DIFFERENTIAL_ANALYSIS.out.plots
    objects  = BIOC_RIBOSOMEPROFILINGQC_RPF_ONLY_DIFFERENTIAL_ANALYSIS.out.objects
    versions = BIOC_RIBOSOMEPROFILINGQC_RPF_ONLY_DIFFERENTIAL_ANALYSIS.out.versions
}
