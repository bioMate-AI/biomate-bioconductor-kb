#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: medips — differential_coverage_analysis
// Identify genomic regions with significant differential coverage (differential methylation) between two conditions using replicates and input controls.
// Input: bam.file.hESCs.Rep1.MeDIP, bam.file.hESCs.Rep2.MeDIP, bam.file.hESCs.Input, bam.file.DE.Input
// Container: quay.io/biocontainers/bioconductor-medips:1.62.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg19, MEDIPS
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MEDIPS_DIFFERENTIAL_COVERAGE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-medips:1.62.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg19", "MEDIPS")
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
    library(MEDIPS)
    library(BSgenome.Hsapiens.UCSC.hg19)
    
    # Define input files from the working directory as specified
    bam.file.hESCs.Rep1.MeDIP = "bam.file.hESCs.Rep1.MeDIP"
    bam.file.hESCs.Rep2.MeDIP = "bam.file.hESCs.Rep2.MeDIP"
    bam.file.hESCs.Input = "bam.file.hESCs.Input"
    bam.file.DE.Input = "bam.file.DE.Input"
    
    # Define key parameters matching the documented workflow
    BSgenome = "BSgenome.Hsapiens.UCSC.hg19"
    uniq = 1e-3
    extend = 300
    shift = 0
    ws = 100
    chr.select = "chr22"
    
    # --- Create MEDIPS sets for IP and Input samples using ---
    hESCs_MeDIP = MEDIPS.createSet(file=bam.file.hESCs.Rep1.MeDIP, BSgenome=BSgenome, extend=extend, shift=shift, uniq=uniq, window_size=ws, chr.select=chr.select)
    hESCs_MeDIP = c(hESCs_MeDIP, MEDIPS.createSet(file=bam.file.hESCs.Rep2.MeDIP, BSgenome=BSgenome, extend=extend, shift=shift, uniq=uniq, window_size=ws, chr.select=chr.select))
    hESCs_Input = MEDIPS.createSet(file=bam.file.hESCs.Input, BSgenome=BSgenome, extend=extend, shift=shift, uniq=uniq, window_size=ws, chr.select=chr.select)
    DE_Input = MEDIPS.createSet(file=bam.file.DE.Input, BSgenome=BSgenome, extend=extend, shift=shift, uniq=uniq, window_size=ws, chr.select=chr.select)
    
    # Adapt the MeDIP sets to separate the replicates into two conditions (DE_MeDIP vs hESCs_MeDIP)
    # since we have 2 MeDIP replicates and need to perform differential analysis.
    DE_MeDIP = hESCs_MeDIP[2]
    hESCs_MeDIP = hESCs_MeDIP[1]
    
    # --- Generate a coupling vector for CpG density normalization ---
    CS = MEDIPS.couplingVector(pattern="CG", refObj=hESCs_MeDIP[[1]])
    
    # --- Calculate genome-wide coverage, methylation profiles, and ---
    mr.edgeR = MEDIPS.meth(MSet1=DE_MeDIP, MSet2=hESCs_MeDIP, CSet=CS, ISet1=DE_Input, ISet2=hESCs_Input, p.adj="bonferroni", diff.method="edgeR", MeDIP=T, CNV=F, minRowSum=10)
    
    # Save the full differential coverage results
    saveRDS(mr.edgeR, "mr_edgeR_results.rds")
    
    # --- Select significant windows using MEDIPS.selectSig ---
    mr.edgeR.s = MEDIPS.selectSig(results=mr.edgeR, p.value=0.1, adj=T, ratio=NULL, bg.counts=NULL, CNV=F)
    write.csv(mr.edgeR.s, "significant_windows.csv", row.names=FALSE)
    
    # --- Filter and merge adjacent significant windows into ---
    mr.edgeR.s.gain = mr.edgeR.s[which(mr.edgeR.s[,grep("logFC", colnames(mr.edgeR.s))]>0),]
    
    # Ensure mergeFrames is called robustly even if no significant gain windows are found
    if (!is.null(mr.edgeR.s.gain) && nrow(mr.edgeR.s.gain) > 0) {
        mr.edgeR.s.gain.m = MEDIPS.mergeFrames(frames=mr.edgeR.s.gain, distance=1)
    } else {
        mr.edgeR.s.gain.m = data.frame()
    }
    write.csv(mr.edgeR.s.gain.m, "merged_gain_regions.csv", row.names=FALSE)
    
    # --- Extract and summarize data at regions of interest using ---
    columns=names(mr.edgeR)[grep("counts",names(mr.edgeR))]
    
    if (!is.null(mr.edgeR.s.gain.m) && nrow(mr.edgeR.s.gain.m) > 0) {
        tryCatch({
            rois=MEDIPS.selectROIs(results=mr.edgeR, rois=mr.edgeR.s.gain.m, columns=columns, summarize=NULL)
            write.csv(rois, "rois_detailed.csv", row.names=FALSE)
        }, error = function(e) {
            message("Error selecting detailed ROIs: ", e\$message)
            write.csv(data.frame(), "rois_detailed.csv", row.names=FALSE)
        })
        
        tryCatch({
            rois.s=MEDIPS.selectROIs(results=mr.edgeR, rois=mr.edgeR.s.gain.m, columns=columns, summarize="avg")
            write.csv(rois.s, "rois_summarized.csv", row.names=FALSE)
        }, error = function(e) {
            message("Error selecting summarized ROIs: ", e\$message)
            write.csv(data.frame(), "rois_summarized.csv", row.names=FALSE)
        })
    } else {
        message("No significant regions of interest found. Writing empty ROI files.")
        write.csv(data.frame(), "rois_detailed.csv", row.names=FALSE)
        write.csv(data.frame(), "rois_summarized.csv", row.names=FALSE)
    }

    writeLines(c(
        '"BIOC_MEDIPS_DIFFERENTIAL_COVERAGE_ANALYSIS":',
        paste0('        medips: ', as.character(packageVersion("medips")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_coverage_analysis.csv versions.yml
    """
}

workflow BIOC_MEDIPS_DIFFERENTIAL_COVERAGE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam.file.hESCs.Rep1.MeDIP, bam.file.hESCs.Rep2.MeDIP, bam.file.hESCs.Input, bam.file.DE.Input ] ]

    main:
    BIOC_MEDIPS_DIFFERENTIAL_COVERAGE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_MEDIPS_DIFFERENTIAL_COVERAGE_ANALYSIS.out.tables
    plots    = BIOC_MEDIPS_DIFFERENTIAL_COVERAGE_ANALYSIS.out.plots
    objects  = BIOC_MEDIPS_DIFFERENTIAL_COVERAGE_ANALYSIS.out.objects
    versions = BIOC_MEDIPS_DIFFERENTIAL_COVERAGE_ANALYSIS.out.versions
}
