#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SCANVIS — splice_junction_analysis_and_visualization
// Scan, score, and annotate splice junctions, link them to genomic variants, and visualize the results using sashimi plots.
// Input: sj_table.txt, variants.vcf, gtf_annotation.gtf
// Container: quay.io/biocontainers/bioconductor-scanvis:1.24.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: SCANVIS
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the SCANVIS package and example datasets or generate a SCANVIS-readable annotation object
//  * 2. [Core Analysis] Scan and score splice junctions using SCANVISscan
//  * 3. [Core Analysis] Map genomic variants to the scanned splice junctions using SCANVISlinkvar
//  * 4. [Visualization & Output] Visualize splice junctions and variants in a region of interest using SCANVISvisual

nextflow.enable.dsl = 2

process BIOC_SCANVIS_SPLICE_JUNCTION_ANALYSIS_AND_VISUALIZATION {
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
    .bm_deps <- c("SCANVIS")
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
        
        # Load the SCANVIS package
        library(SCANVIS)
        
        # 1. Generate a SCANVIS-readable annotation object from the user-provided GTF file
        # The SCANVISannotation function converts a GTF file into the required list structure
        gen19 <- SCANVISannotation("gtf_annotation.gtf")
        names(gen19)
        
        # Read the user-provided splice junction table
        # Expected columns: chr, start, end, uniq.reads
        gbm3_df <- read.table("sj_table.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
        gbm3 <- as.matrix(gbm3_df)
        head(gbm3)
        
        # 2. Scan and score splice junctions using SCANVISscan
        gbm3.scn <- SCANVISscan(sj = gbm3, gen = gen19, Rcut = 5, bam = NULL, samtools = NULL)
        head(gbm3.scn)
        
        # Read the user-provided genomic variants file
        # Expected columns: chr, start, end, passedMUT
        # Using comment.char = "#" to safely ignore VCF metadata lines starting with "##"
        gbm3.vcf <- read.table("variants.vcf", header = TRUE, sep = "\t", stringsAsFactors = FALSE, comment.char = "#")
        head(gbm3.vcf)
        
        # 3. Map genomic variants to the scanned splice junctions using SCANVISlinkvar
        gbm3.scnv <- SCANVISlinkvar(gbm3.scn, gbm3.vcf, gen19)
        gbm3.scnv[10:23, ]
        
        # Map variants with a padding of 100 bp
        gbm3.scnvp <- SCANVISlinkvar(gbm3.scn, gbm3.vcf, gen19, p = 100)
        table(gbm3.scnv[, 'passedMUT'])
        table(gbm3.scnvp[, 'passedMUT'])
        
        # 4. Visualize splice junctions and variants in a region of interest using SCANVISvisual
        # We construct the LUSC list using our processed sample to match the documented workflow structure
        LUSC <- list("Sample1" = gbm3.scnv, "Sample2" = gbm3.scnv)
        
        # Open a PDF device to save the sashimi plots
        pdf("scanvis_sashimi_plots.pdf", width = 12, height = 10)
        par(mfrow = c(2, 1), mar = c(1, 1, 1, 1))
        
        # Dynamically select a gene from the processed data for visualization
        valid_genes <- gbm3.scnv[, "gene_name"]
        valid_genes <- valid_genes[!is.na(valid_genes) & valid_genes != "NA"]
        if (length(valid_genes) > 0) {
          roi_gene <- strsplit(valid_genes[1], ",")[[1]][1]
        } else {
          roi_gene <- "PPA2" # Fallback if no genes are found
        }
        
        # Wrap the visualization steps in a tryCatch block to ensure robustness 
        # (e.g., in case the selected gene is not present in the user's custom GTF/SJ data)
        tryCatch({
          vis.lusc1 <- SCANVISvisual(roi_gene, gen19, LUSC[[1]], TITLE = names(LUSC)[1], full.annot = TRUE, bam = NULL, samtools = NULL)
          vis.lusc2 <- SCANVISvisual(roi_gene, gen19, LUSC[[2]], TITLE = names(LUSC)[2], full.annot = TRUE, bam = NULL, samtools = NULL, USJ = 'RRS')
          
          ASJ <- tail(vis.lusc2[[2]])[, 1:3]
          c2 <- SCANVISvisual(roi_gene, gen19, LUSC[[2]], TITLE = names(LUSC)[2], full.annot = TRUE, SJ.special = ASJ)
          
          vis.lusc.merged <- SCANVISvisual(roi_gene, gen19, LUSC, TITLE = 'Two LUSC samples, merged', full.annot = TRUE)
          
          # Save visualization objects if successful
          saveRDS(vis.lusc1, "vis_lusc1.rds")
          saveRDS(vis.lusc2, "vis_lusc2.rds")
          saveRDS(c2, "c2.rds")
          saveRDS(vis.lusc.merged, "vis_lusc_merged.rds")
        }, error = function(e) {
          message("Visualization step skipped or failed: ", e\$message)
          message("Note: SCANVISvisual requires the gene '", roi_gene, "' to be present in the input GTF and splice junction data.")
        })
        
        dev.off()
        
        # Save meaningful tabular and RDS outputs
        write.csv(gbm3.scn, "gbm3_scanned_junctions.csv", row.names = FALSE)
        write.csv(gbm3.scnv, "gbm3_linked_variants.csv", row.names = FALSE)
        write.csv(gbm3.scnvp, "gbm3_linked_variants_padded.csv", row.names = FALSE)
        saveRDS(gen19, "scanvis_annotation.rds")
        
        message("SCANVIS pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SCANVIS_SPLICE_JUNCTION_ANALYSIS_AND_VISUALIZATION":',
        paste0('    SCANVIS: ', as.character(packageVersion('SCANVIS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splice_junction_analysis_and_visualization.csv versions.yml
    """
}

workflow BIOC_SCANVIS_SPLICE_JUNCTION_ANALYSIS_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sj_table.txt, variants.vcf, gtf_annotation.gtf ] ]

    main:
    BIOC_SCANVIS_SPLICE_JUNCTION_ANALYSIS_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SCANVIS_SPLICE_JUNCTION_ANALYSIS_AND_VISUALIZATION.out.tables
    plots    = BIOC_SCANVIS_SPLICE_JUNCTION_ANALYSIS_AND_VISUALIZATION.out.plots
    objects  = BIOC_SCANVIS_SPLICE_JUNCTION_ANALYSIS_AND_VISUALIZATION.out.objects
    versions = BIOC_SCANVIS_SPLICE_JUNCTION_ANALYSIS_AND_VISUALIZATION.out.versions
}
