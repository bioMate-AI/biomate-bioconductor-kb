library(kissDE)

src_file <- system.file("extdata", "output_kissplice_SNV.fa", package = "kissDE")

if (file.exists(src_file)) {
    file.copy(src_file, "output_kissplice_SNV.fa", overwrite = TRUE)
} else {
    # Fallback: create a synthetic KisSplice FASTA output for SNVs (Type_0)
    # Assuming 4 samples (e.g., 2 conditions, 2 replicates)
    fasta_lines <- c(
        ">bcc_1|Cycle_1|Type_0|upper_path_length_100|C1_50|C2_45|C3_10|C4_15|rank_0.99",
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT",
        ">bcc_1|Cycle_1|Type_0|lower_path_length_100|C1_5|C2_10|C3_40|C4_55|rank_0.99",
        "ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGA",
        ">bcc_2|Cycle_2|Type_0|upper_path_length_100|C1_100|C2_110|C3_105|C4_95|rank_0.85",
        "TGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCA",
        ">bcc_2|Cycle_2|Type_0|lower_path_length_100|C1_10|C2_15|C3_12|C4_14|rank_0.85",
        "TGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCATGCG"
    )
    writeLines(fasta_lines, "output_kissplice_SNV.fa")
}