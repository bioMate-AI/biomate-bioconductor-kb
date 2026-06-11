#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SubCellBarCode — differential_localization
// Compare protein subcellular localization between two conditions (e.g., control vs treatment) and filter high-confidence relocated candidates.
// Input: cls_cond1.tsv, cls_cond2.tsv, psm_cond1.tsv, psm_cond2.tsv, quant_cond1.tsv, quant_cond2.tsv
// Container: quay.io/biocontainers/bioconductor-subcellbarcode:1.26.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SubCellBarCode, htmlwidgets
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Visualize localization shifts between conditions using a sankey plot
//  * 2. [Core Analysis] Filter and identify strong relocated candidates using PSM counts and correlation analysis

nextflow.enable.dsl = 2

process BIOC_SUBCELLBARCODE_DIFFERENTIAL_LOCALIZATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
        
        # Load required library
        library(SubCellBarCode)
        
        # -----------------------------------------------------------------------------
        # Stage 0: Read User Input Files
        # -----------------------------------------------------------------------------
        
        # Read classification output for condition 1
        cls.df <- read.delim("cls_cond1.tsv", sep = "\t", header = TRUE, check.names = FALSE)
        if ("Protein" %in% colnames(cls.df)) {
          rownames(cls.df) <- cls.df\$Protein
        } else {
          rownames(cls.df) <- cls.df[, 1]
        }
        
        # Read classification output for condition 2
        hcc827GEFClass <- read.delim("cls_cond2.tsv", sep = "\t", header = TRUE, check.names = FALSE)
        if ("Protein" %in% colnames(hcc827GEFClass)) {
          rownames(hcc827GEFClass) <- hcc827GEFClass\$Protein
        } else {
          rownames(hcc827GEFClass) <- hcc827GEFClass[, 1]
        }
        
        # Read PSM counts for condition 1
        hcc827CtrlPSMCount <- read.delim("psm_cond1.tsv", sep = "\t", header = TRUE, check.names = FALSE)
        if ("Protein" %in% colnames(hcc827CtrlPSMCount)) {
          rownames(hcc827CtrlPSMCount) <- hcc827CtrlPSMCount\$Protein
        } else {
          rownames(hcc827CtrlPSMCount) <- hcc827CtrlPSMCount[, 1]
        }
        
        # Read PSM counts for condition 2
        hcc827GefPSMCount <- read.delim("psm_cond2.tsv", sep = "\t", header = TRUE, check.names = FALSE)
        if ("Protein" %in% colnames(hcc827GefPSMCount)) {
          rownames(hcc827GefPSMCount) <- hcc827GefPSMCount\$Protein
        } else {
          rownames(hcc827GefPSMCount) <- hcc827GefPSMCount[, 1]
        }
        
        # Read quantification data for condition 1
        hcc827Ctrl <- read.delim("quant_cond1.tsv", sep = "\t", header = TRUE, row.names = 1, check.names = FALSE)
        
        # Read quantification data for condition 2
        hcc827GEF <- read.delim("quant_cond2.tsv", sep = "\t", header = TRUE, row.names = 1, check.names = FALSE)
        
        
        # -----------------------------------------------------------------------------
        # Stage 1: Visualize localization shifts between conditions using a sankey plot
        # -----------------------------------------------------------------------------
        
        sk_plot <- sankeyPlot(sampleCls1 = cls.df, sampleCls2 = hcc827GEFClass)
        htmlwidgets::saveWidget(sk_plot, "sankey_plot.html")
        
        
        # -----------------------------------------------------------------------------
        # Stage 2: Filter and identify strong relocated candidates
        # -----------------------------------------------------------------------------
        
        # Candidate identification without annotation (standard settings)
        pdf("candidate_relocated_plot.pdf", width = 8, height = 6)
        candidate.df <- candidateRelocatedProteins(sampleCls1 = cls.df, 
                                        s1PSM = hcc827CtrlPSMCount, 
                                        s1Quant = hcc827Ctrl,
                                        sampleCls2 = hcc827GEFClass,
                                        s2PSM = hcc827GefPSMCount,
                                        s2Quant = hcc827GEF,
                                        min.psm = 2,
                                        pearson.cor = 0.8)
        dev.off()
        
        # Save candidate dataframe to file
        write.table(candidate.df, "candidate_proteins.tsv", sep = "\t", quote = FALSE, row.names = FALSE)
        
        
        # Candidate identification with annotation and custom thresholds
        pdf("candidate_relocated_annotated_plot.pdf", width = 8, height = 6)
        candidate2.df <- candidateRelocatedProteins(sampleCls1 = cls.df,
                                        s1PSM = hcc827CtrlPSMCount, 
                                        s1Quant = hcc827Ctrl, 
                                        sampleCls2 = hcc827GEFClass, 
                                        s2PSM = hcc827GefPSMCount, 
                                        s2Quant = hcc827GEF, 
                                        annotation = TRUE, 
                                        min.psm = 9, 
                                        pearson.cor = 0.05)
        dev.off()
        
        # Save annotated candidate dataframe to file
        write.table(candidate2.df, "candidate_proteins_annotated.tsv", sep = "\t", quote = FALSE, row.names = FALSE)
        
        # Save RDS objects for downstream analysis
        saveRDS(candidate.df, "candidate_proteins.rds")
        saveRDS(candidate2.df, "candidate_proteins_annotated.rds")

    writeLines(c(
        '"BIOC_SUBCELLBARCODE_DIFFERENTIAL_LOCALIZATION":',
        paste0('    SubCellBarCode: ', as.character(packageVersion('SubCellBarCode')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_differential_localization.csv versions.yml
    """
}

workflow BIOC_SUBCELLBARCODE_DIFFERENTIAL_LOCALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cls_cond1.tsv, cls_cond2.tsv, psm_cond1.tsv, psm_cond2.tsv, quant_cond1.tsv, quant_cond2.tsv ] ]

    main:
    BIOC_SUBCELLBARCODE_DIFFERENTIAL_LOCALIZATION(ch_input)

    emit:
    tables   = BIOC_SUBCELLBARCODE_DIFFERENTIAL_LOCALIZATION.out.tables
    plots    = BIOC_SUBCELLBARCODE_DIFFERENTIAL_LOCALIZATION.out.plots
    objects  = BIOC_SUBCELLBARCODE_DIFFERENTIAL_LOCALIZATION.out.objects
    versions = BIOC_SUBCELLBARCODE_DIFFERENTIAL_LOCALIZATION.out.versions
}
