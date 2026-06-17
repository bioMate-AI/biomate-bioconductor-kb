#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: raer — bulk_differential_editing
// Quantify editing sites in bulk RNA-seq and identify condition-specific differential editing events.
// Input: Control_1.bam, Control_2.bam, Treatment_1.bam, Treatment_2.bam, fafn.fasta, chr_18_editing_sites.gr
// Container: quay.io/biocontainers/bioconductor-raer:1.8.0--r45h01b2380_2
// R packages: ComplexHeatmap, GenomicRanges, SummarizedExperiment, raer, rtracklayer
// Bioconductor: 3.20 | R: 4.4
// Requires: ComplexHeatmap, GenomicRanges, SummarizedExperiment, raer, rtracklayer
// Visualizations: heatmap (ComplexHeatmap), heatmap
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Configure filtering parameters using FilterParam()
//  * 2. [Core Analysis] Quantify base counts at editing sites across samples using pileup_sites()
//  * 3. [Core Analysis] Calculate editing frequencies and depth using calc_edit_frequency()
//  * 4. [Core Analysis] Filter out low-frequency or low-depth sites
//  * 5. [Input & Preparation] Create a differential editing object using make_de_object()
//  * 6. [Core Analysis] Identify differentially edited sites using find_de_sites()

nextflow.enable.dsl = 2

process BIOC_RAER_BULK_DIFFERENTIAL_EDITING {
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
    .bm_deps <- c("ComplexHeatmap", "GenomicRanges", "SummarizedExperiment", "raer", "rtracklayer")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM, jammy)
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
            library(raer)
            library(SummarizedExperiment)
            library(GenomicRanges)
            library(rtracklayer)
            
            # 1. Read User Input Files
            # Read all BAM files in the current directory to represent actual biological replicates
            bam_files <- list.files(pattern = "\\\\.bam\$", full.names = TRUE)
            names(bam_files) <- tools::file_path_sans_ext(basename(bam_files))

            # Ensure each BAM is coordinate-indexed (raer::pileup_sites requires a .bai
            # next to each BAM; inputs may arrive without one).
            for (.b in bam_files) if (!file.exists(paste0(.b, ".bai"))) Rsamtools::indexBam(.b)
            
            fafn <- "fafn.fasta"
            sites_file <- "chr_18_editing_sites.gr"
            
            # Read the GRanges object of known editing sites using readRDS for serialized R objects
            chr_18_editing_sites <- readRDS(sites_file)
            
            # 2. Configure Filtering Parameters
            fp <- FilterParam(
                only_keep_variants = TRUE, # only report sites with variants
                trim_5p = 5, # bases to remove from 5' or 3' end
                trim_3p = 5,
                min_base_quality = 30, # minimum base quality score
                min_mapq = 255, # minimum MAPQ read score
                library_type = "fr-first-strand", # library type
                min_splice_overhang = 10 # minimum required splice site overhang
            )
            
            # 3. Quantify Base Counts at Editing Sites Across Samples
            rse <- pileup_sites(bam_files,
                fasta = fafn,
                sites = chr_18_editing_sites,
                chroms = as.character(unique(seqnames(chr_18_editing_sites))),
                param = fp
            )
            
            # Add sample metadata required for downstream differential analysis
            # Extract condition dynamically from filename (e.g., "Wildtype_1" -> "Wildtype")
            colData(rse)\$sample <- names(bam_files)
            conds <- gsub("[_0-9]+\$", "", names(bam_files))
            
            # Fallback if pattern is not met and fewer than 2 conditions are found
            if (length(unique(conds)) < 2) {
                half <- ceiling(length(bam_files) / 2)
                conds <- rep(c("Control", "Treatment"), c(half, length(bam_files) - half))
            }
            colData(rse)\$condition <- as.factor(conds)
            
            # 4. Calculate Editing Frequencies and Depth
            rse <- calc_edit_frequency(rse,
                edit_from = "A",
                edit_to = "G",
                drop = TRUE
            )
            
            # 5. Filter Out Low-Frequency or Low-Depth Sites
            has_editing <- rowSums(assay(rse, "edit_freq") > 0) >= 1
            has_depth <- rowSums(assay(rse, "depth") >= 5) == ncol(rse)
            rse <- rse[has_editing & has_depth, ]
            
            # 6. Create a Differential Editing Object
            deobj <- make_de_object(rse, min_prop = 0.05, min_samples = 3)
            deobj\$sample <- factor(deobj\$sample)
            
            # 7. Identify Differentially Edited Sites
            cond_levels <- levels(colData(rse)\$condition)
            
            de_results <- find_de_sites(deobj,
                test = "DESeq2",
                sample_col = "sample",
                condition_col = "condition",
                condition_control = cond_levels[1],
                condition_treatment = cond_levels[2]
            )
            
            # 8. Save Outputs
            # Save the full differential editing results object
            saveRDS(de_results, "de_results.rds")
            
            # Save the significant results table as a CSV
            if (!is.null(de_results\$sig_results)) {
                write.csv(as.data.frame(de_results\$sig_results), "significant_de_sites.csv", row.names = TRUE)
            }
            
            # Generate and save a heatmap of editing frequencies for the top differentially edited sites
            pdf("top_differentially_edited_sites_heatmap.pdf", width = 6, height = 8)
            tryCatch({
                library(ComplexHeatmap)
                if (!is.null(de_results\$sig_results) && nrow(de_results\$sig_results) > 0) {
                    top_sites <- rownames(de_results\$sig_results)[1:min(20, nrow(de_results\$sig_results))]
                    hp <- Heatmap(assay(rse, "edit_freq")[top_sites, , drop = FALSE],
                        name = "editing frequency",
                        column_labels = paste0(rse\$condition, "-", rse\$sample)
                    )
                    draw(hp)
                }
            }, error = function(e) {
                # Fallback to base R heatmap if ComplexHeatmap is not available or fails
                if (!is.null(de_results\$sig_results) && nrow(de_results\$sig_results) > 0) {
                    top_sites <- rownames(de_results\$sig_results)[1:min(20, nrow(de_results\$sig_results))]
                    heatmap(assay(rse, "edit_freq")[top_sites, , drop = FALSE],
                        labCol = paste0(rse\$condition, "-", rse\$sample),
                        main = "Editing Frequency"
                    )
                }
            })
            dev.off()

    writeLines(c(
        '"BIOC_RAER_BULK_DIFFERENTIAL_EDITING":',
        paste0('    raer: ', as.character(packageVersion('raer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_bulk_differential_editing.csv versions.yml
    """
}

workflow BIOC_RAER_BULK_DIFFERENTIAL_EDITING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ bam_files.bam, fafn.fasta, chr_18_editing_sites.gr ] ]

    main:
    BIOC_RAER_BULK_DIFFERENTIAL_EDITING(ch_input)

    emit:
    tables   = BIOC_RAER_BULK_DIFFERENTIAL_EDITING.out.tables
    plots    = BIOC_RAER_BULK_DIFFERENTIAL_EDITING.out.plots
    objects  = BIOC_RAER_BULK_DIFFERENTIAL_EDITING.out.objects
    versions = BIOC_RAER_BULK_DIFFERENTIAL_EDITING.out.versions
}
