#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qcmetrics — n15_labeled_proteomics_qc
// Perform quality control on processed N15 metabolic labeling proteomics data, evaluating incorporation rate, log2 fold-changes, and feature counts.
// Input: n15psm.rda
// Container: quay.io/biocontainers/bioconductor-qcmetrics:1.48.0--r45hdfd78af_0
// R packages: MSnbase, ggplot2, qcmetrics
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase, ggplot2, qcmetrics
// Visualizations: bar plot, array QC report
// QC: array detection QC
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the N15 PSM dataset
//  * 2. [Visualization & Output] Create the N15 incorporation rate QC metric with custom show and plot methods
//  * 3. [Core Analysis] Combine features to peptide and protein levels and calculate log2 fold-changes
//  * 4. [Visualization & Output] Create the log2 fold-change QC metric with custom show and plot methods
//  * 5. [Input & Preparation] Create the feature count QC metric
//  * 6. [Visualization & Output] Combine all metrics and generate the final report

nextflow.enable.dsl = 2

process BIOC_QCMETRICS_N15_LABELED_PROTEOMICS_QC {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("MSnbase", "ggplot2", "qcmetrics")
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
    
    # 1. Load the N15 PSM dataset
    library("ggplot2")
    library("MSnbase")
    library("qcmetrics")
    
    # Read the user input file from the working directory
    # This file contains the MSnSet object (typically named 'psm' or 'n15psm')
    load("n15psm.rda")
    
    # Ensure the object is named 'psm' as expected by the pipeline
    if (!exists("psm") && exists("n15psm")) {
        psm <- n15psm
    }
    
    # 2. Create the N15 incorporation rate QC metric with custom show and plot methods
    qcinc <- QcMetric(name = "15N incorporation rate")
    qcdata(qcinc, "inc") <- fData(psm)\$inc
    qcdata(qcinc, "tr") <- 97.5
    status(qcinc) <- median(qcdata(qcinc, "inc")) > qcdata(qcinc, "tr")
    
    show(qcinc) <- function(object) {
        qcshow(object, qcdata = FALSE)
        cat(" QC threshold:", qcdata(object, "tr"), "\n")
        cat(" Incorporation rate\n")
        print(summary(qcdata(object, "inc")))
        invisible(NULL)
    }
    
    plot(qcinc) <- function(object) {
        inc <- qcdata(object, "inc")
        tr <- qcdata(object, "tr")
        lab <- "Incorporation rate"
        dd <- data.frame(inc = qcdata(qcinc, "inc"))
        p <- ggplot(dd, aes(factor(""), inc)) +
            geom_jitter(colour = "#4582B370", size = 3) +
        geom_boxplot(fill = "#FFFFFFD0", colour = "#000000",
                     outlier.size = 0) +
        geom_hline(yintercept = tr, colour = "red",
                   linetype = "dotted", size = 1) +
        labs(x = "", y = "Incorporation rate")
        p
    }
    
    # 3. Combine features to peptide and protein levels and calculate log2 fold-changes
    fData(psm)\$modseq <- paste(fData(psm)\$Peptide_Sequence, fData(psm)\$Variable_Modifications, sep = "+")
    pep <- combineFeatures(psm, as.character(fData(psm)\$Peptide_Sequence), "median", verbose = FALSE)
    modpep <- combineFeatures(psm, fData(psm)\$modseq, "median", verbose = FALSE)
    prot <- combineFeatures(psm, as.character(fData(psm)\$Protein_Accession), "median", verbose = FALSE)
    
    # 4. Create the log2 fold-change QC metric with custom show and plot methods
    qclfc <- QcMetric(name = "Log2 fold-changes")
    qcdata(qclfc, "lfc.psm") <- log2(exprs(psm)[,"unlabelled"] / exprs(psm)[, "N15"])
    qcdata(qclfc, "lfc.pep") <- log2(exprs(pep)[,"unlabelled"] / exprs(pep)[, "N15"])
    qcdata(qclfc, "lfc.modpep") <- log2(exprs(modpep)[,"unlabelled"] / exprs(modpep)[, "N15"])
    qcdata(qclfc, "lfc.prot") <- log2(exprs(prot)[,"unlabelled"] / exprs(prot)[, "N15"])
    qcdata(qclfc, "explfc") <- c(-0.5, 0.5)
    status(qclfc) <- median(qcdata(qclfc, "lfc.psm")) > qcdata(qclfc, "explfc")[1] & median(qcdata(qclfc, "lfc.psm")) < qcdata(qclfc, "explfc")[2]
    
    show(qclfc) <- function(object) {
        qcshow(object, qcdata = FALSE)
        cat(" QC thresholds:", qcdata(object, "explfc"), "\n")
        cat(" * PSM log2 fold-changes\n")
        print(summary(qcdata(object, "lfc.psm")))
        cat(" * Modified peptide log2 fold-changes\n")
        print(summary(qcdata(object, "lfc.modpep")))
        cat(" * Peptide log2 fold-changes\n")
        print(summary(qcdata(object, "lfc.pep")))
        cat(" * Protein log2 fold-changes\n")
        print(summary(qcdata(object, "lfc.prot")))
        invisible(NULL)
    }
    
    plot(qclfc) <- function(object) {
        x <- qcdata(object, "explfc")
        plot(density(qcdata(object, "lfc.psm")), main = "", sub = "", col = "red", ylab = "", lwd = 2, xlab = expression(log[2]~fold-change))
        lines(density(qcdata(object, "lfc.modpep")), col = "steelblue", lwd = 2)
        lines(density(qcdata(object, "lfc.pep")), col = "blue", lwd = 2)
        lines(density(qcdata(object, "lfc.prot")), col = "orange")
        abline(h = 0, col = "grey")
        abline(v = 0, lty = "dotted")
        rect(x[1], -1, x[2], 1, col = "#EE000030", border = NA)
        abline(v = median(qcdata(object, "lfc.psm")), lty = "dashed", col = "blue")
        legend("topright", c("PSM", "Peptides", "Modified peptides", "Proteins"), col = c("red", "steelblue", "blue", "orange"), lwd = 2, bty = "n")
    }
    
    # 5. Create the feature count QC metric
    qcnb <- QcMetric(name = "Number of features")
    qcdata(qcnb, "count") <- c(PSM = nrow(psm), ModPep = nrow(modpep), Pep = nrow(pep), Prot = nrow(prot))
    qcdata(qcnb, "peptab") <- table(fData(psm)\$Peptide_Sequence)
    qcdata(qcnb, "modpeptab") <- table(fData(psm)\$modseq)
    qcdata(qcnb, "upep.per.prot") <- fData(psm)\$Number_Of_Unique_Peptides
    
    show(qcnb) <- function(object) {
        qcshow(object, qcdata = FALSE)
        print(qcdata(object, "count"))
    }
    
    plot(qcnb) <- function(object) {
        par(mar = c(5, 4, 2, 1))
        layout(matrix(c(1, 2, 1, 3, 1, 4), ncol = 3))
        barplot(qcdata(object, "count"), horiz = TRUE, las = 2)
        barplot(table(qcdata(object, "modpeptab")), xlab = "Modified peptides")
        barplot(table(qcdata(object, "peptab")), xlab = "Peptides")
        barplot(table(qcdata(object, "upep.per.prot")), xlab = "Unique peptides per protein ")
    }
    
    # 6. Combine all metrics and generate the final report
    n15qcm <- QcMetrics(qcdata = list(qcinc, qclfc, qcnb))
    
    # Generate the report using the exact documented call
    qcReport(n15qcm, reportname = "n15qcreport", 
             title = expinfo(experimentData(psm))["title"], 
             author = expinfo(experimentData(psm))["contact"], 
             clean = FALSE)
    
    # 7. Write additional named output files for downstream analysis
    saveRDS(n15qcm, file = "n15qcm.rds")
    
    # Export combined features as CSV tables
    write.csv(as.data.frame(exprs(pep)), file = "combined_peptides.csv", row.names = TRUE)
    write.csv(as.data.frame(exprs(modpep)), file = "combined_modified_peptides.csv", row.names = TRUE)
    write.csv(as.data.frame(exprs(prot)), file = "combined_proteins.csv", row.names = TRUE)
    
    # Export individual QC plots as PDFs
    pdf("qc_incorporation_rate.pdf", width = 6, height = 6)
    print(plot(qcinc))
    dev.off()
    
    pdf("qc_log2_fold_changes.pdf", width = 6, height = 6)
    plot(qclfc)
    dev.off()
    
    pdf("qc_feature_counts.pdf", width = 8, height = 6)
    plot(qcnb)
    dev.off()

    writeLines(c(
        '"BIOC_QCMETRICS_N15_LABELED_PROTEOMICS_QC":',
        paste0('    qcmetrics: ', as.character(packageVersion('qcmetrics')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_n15_labeled_proteomics_qc.csv versions.yml
    """
}

workflow BIOC_QCMETRICS_N15_LABELED_PROTEOMICS_QC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ n15psm.rda ] ]

    main:
    BIOC_QCMETRICS_N15_LABELED_PROTEOMICS_QC(ch_input)

    emit:
    tables   = BIOC_QCMETRICS_N15_LABELED_PROTEOMICS_QC.out.tables
    plots    = BIOC_QCMETRICS_N15_LABELED_PROTEOMICS_QC.out.plots
    objects  = BIOC_QCMETRICS_N15_LABELED_PROTEOMICS_QC.out.objects
    versions = BIOC_QCMETRICS_N15_LABELED_PROTEOMICS_QC.out.versions
}
