#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CATALYST — preprocessing_and_deconvolution
// Perform bead-based normalization, single-cell debarcoding, and spillover compensation on raw mass cytometry data, followed by exporting back to FCS files.
// Input: raw_data.fcs, sample_ff.fcs, sample_key.csv, ss_exp.fcs, mp_cells.fcs
// Container: quay.io/biocontainers/bioconductor-catalyst:1.34.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CATALYST, SingleCellExperiment, cowplot, flowCore, ggplot2
// Visualizations: scatter plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Ingest raw data and convert to SingleCellExperiment using prepData. 2. Perform bead-based normalization using normCytof. 3. Assign

nextflow.enable.dsl = 2

process BIOC_CATALYST_PREPROCESSING_AND_DECONVOLUTION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
            
            # Load required libraries
            library(CATALYST)
            library(flowCore)
            library(ggplot2)
            library(cowplot)
            
            # ==========================================
            # 1. Load User Input Files
            # ==========================================
            
            # Read FCS files
            raw_data  <- read.FCS("raw_data.fcs", transformation = FALSE, truncate_max_range = FALSE)
            sample_ff <- read.FCS("sample_ff.fcs", transformation = FALSE, truncate_max_range = FALSE)
            ss_exp    <- read.FCS("ss_exp.fcs", transformation = FALSE, truncate_max_range = FALSE)
            mp_cells  <- read.FCS("mp_cells.fcs", transformation = FALSE, truncate_max_range = FALSE)
            
            # Read barcoding key (CSV)
            # The debarcoding scheme should be a binary matrix with sample IDs as row names and numeric barcode masses as column names
            sample_key_df <- read.csv("sample_key.csv", row.names = 1, check.names = FALSE)
            sample_key    <- as.matrix(sample_key_df)
            
            # ==========================================
            # 2. Normalization
            # ==========================================
            
            sce <- prepData(raw_data)
            res <- normCytof(sce, beads = "dvs", k = 50, assays = c("counts", "exprs"), overwrite = FALSE)
            sce <- res\$data
            
            # Save normalization outputs
            saveRDS(sce, "normalized_sce.rds")
            if (!is.null(res\$scatter)) {
                ggsave("normalization_scatter.pdf", plot = res\$scatter, width = 8, height = 6)
            }
            if (!is.null(res\$lines)) {
                ggsave("normalization_lines.pdf", plot = res\$lines, width = 8, height = 6)
            }
            
            # ==========================================
            # 3. Debarcoding
            # ==========================================
            
            sce <- prepData(sample_ff)
            sce <- assignPrelim(sce, sample_key)
            sce <- estCutoffs(sce)
            sce2 <- applyCutoffs(sce)
            sce3 <- applyCutoffs(sce, sep_cutoffs = 0.35)
            
            # Compare yields before and after applying global / population-specific cutoffs
            print(c(specific = mean(sce2\$bc_id != 0), global = mean(sce3\$bc_id != 0)))
            
            sce <- sce2
            
            # Save debarcoding outputs
            saveRDS(sce, "debarcoded_sce.rds")
            
            # Generate and save yield plot
            pdf("debarcoding_yields.pdf", width = 10, height = 8)
            print(plotYields(sce, which = 0))
            dev.off()
            
            # ==========================================
            # 4. Compensation
            # ==========================================
            
            sce_ss <- prepData(ss_exp)
            
            # Dynamically extract single-stain mass channels from the ss_exp file
            bc_ms <- as.numeric(gsub("[^0-9]", "", rowData(sce_ss)\$channel_name))
            bc_ms <- sort(unique(bc_ms[!is.na(bc_ms) & bc_ms >= 75 & bc_ms <= 209]))
            
            sce_ss <- assignPrelim(sce_ss, bc_ms, verbose = FALSE)
            sce_ss <- applyCutoffs(estCutoffs(sce_ss))
            sce_ss <- computeSpillmat(sce_ss)
            sm <- metadata(sce_ss)\$spillover_matrix
            
            # Save spillover matrix and plot
            write.csv(sm, "spillover_matrix.csv")
            pdf("spillover_matrix.pdf", width = 10, height = 8)
            print(plotSpillmat(sce_ss))
            dev.off()
            
            # Compensate the multiplexed cells
            sce <- prepData(mp_cells)
            sce <- compCytof(sce, sm, method = "nnls", overwrite = FALSE)
            
            # Save compensated SingleCellExperiment
            saveRDS(sce, "compensated_sce.rds")
            
            # ==========================================
            # 5. Exporting FCS
            # ==========================================
            
            # Export the debarcoded data
            sce <- readRDS("debarcoded_sce.rds")
            sce <- sce[, sce\$bc_id != 0]
            fs <- sce2fcs(sce, split_by = "bc_id")
            
            # Write each flowFrame in the flowSet to an FCS file
            ids <- fsApply(fs, identifier)
            for (id in ids) {
                ff <- fs[[id]]
                fn <- sprintf("demux_sample_%s.fcs", id)
                write.FCS(ff, fn)
            }
    
            # Export the compensated data
            sce_comp <- readRDS("compensated_sce.rds")
            ff_comp <- sce2fcs(sce_comp, assay = "compcounts")
            write.FCS(ff_comp, "compensated_mp_cells.fcs")

    writeLines(c(
        '"BIOC_CATALYST_PREPROCESSING_AND_DECONVOLUTION":',
        paste0('    CATALYST: ', as.character(packageVersion('CATALYST')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_preprocessing_and_deconvolution.csv versions.yml
    """
}

workflow BIOC_CATALYST_PREPROCESSING_AND_DECONVOLUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_data.fcs, sample_ff.fcs, sample_key.csv, ss_exp.fcs, mp_cells.fcs ] ]

    main:
    BIOC_CATALYST_PREPROCESSING_AND_DECONVOLUTION(ch_input)

    emit:
    tables   = BIOC_CATALYST_PREPROCESSING_AND_DECONVOLUTION.out.tables
    plots    = BIOC_CATALYST_PREPROCESSING_AND_DECONVOLUTION.out.plots
    objects  = BIOC_CATALYST_PREPROCESSING_AND_DECONVOLUTION.out.objects
    versions = BIOC_CATALYST_PREPROCESSING_AND_DECONVOLUTION.out.versions
}
