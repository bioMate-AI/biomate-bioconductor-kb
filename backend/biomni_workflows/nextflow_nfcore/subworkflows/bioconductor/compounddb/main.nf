#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: CompoundDb — metabolomics_compound_db_annotation
// Create a custom compound and ion database from metabolomics feature intensity data, annotate features with expected adduct m/z values, and perform differential 
// Input: intensity.csv, coldata.csv
// Container: 1.14.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: CompoundDb, RSQLite, S4Vectors
// Visualizations: plot (ggplot/base)
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_COMPOUNDDB_METABOLOMICS_COMPOUND_DB_ANNOTATION {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-metabolomics:3.20"

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
    library(CompoundDb)
    library(RSQLite)
    library(S4Vectors)
    
    # ==========================================
    # STAGE 1: Load and Preprocess Input Data
    # ==========================================
    
    # Read intensity matrix and sample metadata
    intensity_data <- read.csv("intensity.csv", check.names = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE)
    
    # Extract feature IDs and format intensity matrix
    if ("feature_id" %in% colnames(intensity_data)) {
        feature_ids <- intensity_data\$feature_id
        rownames(intensity_data) <- feature_ids
        intensity_matrix <- intensity_data[, setdiff(colnames(intensity_data), "feature_id"), drop = FALSE]
    } else {
        feature_ids <- rownames(intensity_data)
        intensity_matrix <- intensity_data
    }
    
    message("Loaded ", length(feature_ids), " features and ", ncol(intensity_matrix), " samples.")
    
    # ==========================================
    # STAGE 2: Generate Custom Compound Annotations
    # ==========================================
    
    # Generate deterministic mock chemical formulas and exact masses for the features
    set.seed(42)
    n_features <- length(feature_ids)
    
    # Standard formulas and monoisotopic masses for simulation
    formula_pool <- c("C6H12O6", "C8H10N4O2", "C10H16N5O13P3", "C11H12N2O2", "C3H7NO2", "C9H11NO3")
    mass_map <- c(
        "C6H12O6" = 180.063388,
        "C8H10N4O2" = 194.080376,
        "C10H16N5O13P3" = 507.003556,
        "C11H12N2O2" = 204.089878,
        "C3H7NO2" = 89.047678,
        "C9H11NO3" = 181.073893
    )
    
    selected_formulas <- sample(formula_pool, n_features, replace = TRUE)
    selected_masses <- mass_map[selected_formulas]
    
    # Create compound annotation data frame
    compounds_df <- data.frame(
        compound_id = paste0("CMP_", seq_len(n_features)),
        name = feature_ids,
        inchi = NA_character_,
        inchikey = NA_character_,
        formula = selected_formulas,
        exactmass = selected_masses,
        stringsAsFactors = FALSE
    )
    
    # ==========================================
    # STAGE 3: Build CompDb and IonDb Databases
    # ==========================================
    
    # Initialize an empty SQLite database file
    db_file <- tempfile(fileext = ".sqlite")
    mydb <- emptyCompDb(db_file)
    
    # Insert compound annotations into the CompDb
    mydb <- insertCompound(mydb, compounds_df)
    
    # Connect to the SQLite database to upgrade it to an IonDb
    con <- dbConnect(SQLite(), db_file)
    idb <- IonDb(con, mydb)
    
    # Calculate expected m/z values for positive adducts
    adducts_to_calculate <- c("[M+H]+", "[M+Na]+")
    mzs <- mass2mz(mydb, adduct = adducts_to_calculate, name = "compound_id")
    
    # Create ion annotation data frame with simulated retention times
    ion_df <- data.frame()
    for (add in adducts_to_calculate) {
        tmp <- data.frame(
            compound_id = rownames(mzs),
            ion_adduct = add,
            ion_mz = mzs[, add],
            ion_rt = runif(nrow(mzs), min = 60, max = 600), # Simulated RT in seconds
            stringsAsFactors = FALSE
        )
        ion_df <- rbind(ion_df, tmp)
    }
    
    # Insert ions into the IonDb
    idb <- insertIon(idb, ion_df)
    
    # ==========================================
    # STAGE 4: Query Database and Annotate Features
    # ==========================================
    
    # Retrieve full ion and compound annotations from the IonDb
    annotated_ions <- ions(idb, columns = c("compound_id", "name", "formula", "exactmass", "ion_adduct", "ion_mz", "ion_rt"))
    
    # Merge annotations with the original intensity matrix
    intensity_df <- as.data.frame(intensity_matrix)
    intensity_df\$feature_id <- rownames(intensity_df)
    
    merged_data <- merge(annotated_ions, intensity_df, by.x = "name", by.y = "feature_id")
    
    # ==========================================
    # STAGE 5: Downstream Group Comparison
    # ==========================================
    
    # Perform simple group comparison if condition metadata is available
    if ("sample" %in% colnames(coldata) && "condition" %in% colnames(coldata)) {
        unique_conditions <- unique(coldata\$condition)
        if (length(unique_conditions) >= 2) {
            cond1_samples <- coldata\$sample[coldata\$condition == unique_conditions[1]]
            cond2_samples <- coldata\$sample[coldata\$condition == unique_conditions[2]]
            
            # Intersect with available columns in intensity matrix
            cond1_cols <- intersect(cond1_samples, colnames(intensity_matrix))
            cond2_cols <- intersect(cond2_samples, colnames(intensity_matrix))
            
            if (length(cond1_cols) > 0 && length(cond2_cols) > 0) {
                mean_cond1 <- rowMeans(merged_data[, cond1_cols, drop = FALSE], na.rm = TRUE)
                mean_cond2 <- rowMeans(merged_data[, cond2_cols, drop = FALSE], na.rm = TRUE)
                
                merged_data\$mean_cond1 <- mean_cond1
                merged_data\$mean_cond2 <- mean_cond2
                merged_data\$log2FC <- log2((mean_cond1 + 1) / (mean_cond2 + 1))
                message("Calculated Log2 Fold Change between ", unique_conditions[1], " and ", unique_conditions[2])
            }
        }
    }
    
    # ==========================================
    # STAGE 6: Export Outputs and Visualization
    # ==========================================
    
    # Write the annotated intensity table
    write.csv(merged_data, "annotated_intensities.csv", row.names = FALSE)
    
    # Disconnect from database and copy the SQLite file to the final output path
    dbDisconnect(con)
    file.copy(db_file, "compound_db.sqlite", overwrite = TRUE)
    
    # Generate diagnostic plot of m/z vs Retention Time
    pdf("mz_vs_rt_plot.pdf", width = 8, height = 6)
    if (nrow(merged_data) > 0) {
        formulas_factor <- as.factor(merged_data\$formula)
        plot(
            merged_data\$ion_rt, 
            merged_data\$ion_mz,
            col = as.numeric(formulas_factor) + 1,
            pch = 19,
            cex = 1.2,
            xlab = "Retention Time (seconds)",
            ylab = "m/z",
            main = "Metabolite Ions: m/z vs Retention Time"
        )
        grid()
        legend(
            "topright", 
            legend = levels(formulas_factor),
            col = seq_along(levels(formulas_factor)) + 1, 
            pch = 19, 
            title = "Chemical Formula"
        )
    } else {
        plot(1, 1, type = "n", main = "No annotated ions found to plot")
    }
    dev.off()
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_COMPOUNDDB_METABOLOMICS_COMPOUND_DB_ANNOTATION":',
        paste0('    CompoundDb: ', as.character(packageVersion('CompoundDb')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_metabolomics_compound_db_annotation.csv versions.yml
    """
}

workflow BIOC_COMPOUNDDB_METABOLOMICS_COMPOUND_DB_ANNOTATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_COMPOUNDDB_METABOLOMICS_COMPOUND_DB_ANNOTATION(ch_input)

    emit:
    tables   = BIOC_COMPOUNDDB_METABOLOMICS_COMPOUND_DB_ANNOTATION.out.tables
    plots    = BIOC_COMPOUNDDB_METABOLOMICS_COMPOUND_DB_ANNOTATION.out.plots
    objects  = BIOC_COMPOUNDDB_METABOLOMICS_COMPOUND_DB_ANNOTATION.out.objects
    versions = BIOC_COMPOUNDDB_METABOLOMICS_COMPOUND_DB_ANNOTATION.out.versions
}
