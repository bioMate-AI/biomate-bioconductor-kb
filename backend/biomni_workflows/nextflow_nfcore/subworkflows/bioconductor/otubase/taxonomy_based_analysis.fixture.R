library("OTUbase")

# The workflow expects these files in the working directory.
# We first attempt to copy them from the package's extdata directory.
dirPath <- system.file("extdata/Sogin_2006", package="OTUbase")
files_to_copy <- c("sogin.groups", "sogin.unique.fix.tax", "sogin.names", "sample_metadata.txt", "sogin.fasta")

for (f in files_to_copy) {
    src <- file.path(dirPath, f)
    if (file.exists(src)) {
        file.copy(src, f, overwrite = TRUE)
    }
}

# Fallback: Generate synthetic files if they are not shipped in the installed package
if (!file.exists("sogin.groups")) {
    writeLines(c(
        "D4WT9DQ06DVGFR\t53R",
        "D4WT9DQ05C6YNI\t53R",
        "D4WT9DQ12HNQY2\t115R",
        "D4WT9DQ01AP0UQ\tFS312",
        "D4WT9DQ09FLPTJ\t112R",
        "D27LU0R02A82DK\tFS312"
    ), "sogin.groups")
}

if (!file.exists("sogin.unique.fix.tax")) {
    writeLines(c(
        "D4WT9DQ06DVGFR\tRoot\troot\t1.0\tBacteria\tdomain\t0.91\tProteobacteria\tphylum\t0.62\tGammaproteobacteria\tclass\t0.46\tOceanospirillales\torder\t0.07\tHalomonadaceae\tfamily\t0.06\tModicisalibacter\tgenus\t0.03",
        "D4WT9DQ05C6YNI\tRoot\troot\t1.0\tBacteria\tdomain\t0.91\tActinobacteria\tphylum\t0.10\tActinobacteria\tclass\t0.10\tBifidobacteriales\torder\t0.04\tBifidobacteriaceae\tfamily\t0.04\tMetascardovia\tgenus\t0.04",
        "D4WT9DQ12HNQY2\tRoot\troot\t1.0\tBacteria\tdomain\t0.96\tActinobacteria\tphylum\t0.16\tActinobacteria\tclass\t0.16\tBifidobacteriales\torder\t0.06\tBifidobacteriaceae\tfamily\t0.06\tParascardovia\tgenus\t0.02",
        "D4WT9DQ01AP0UQ\tRoot\troot\t1.0\tBacteria\tdomain\t1.00\tProteobacteria\tphylum\t1.00\tDeltaproteobacteria\tclass\t1.00\tDesulfobacterales\torder\t1.00\tDesulfobulbaceae\tfamily\t1.00\tDesulfocapsa\tgenus\t1.00",
        "D4WT9DQ09FLPTJ\tRoot\troot\t1.0\tBacteria\tdomain\t1.00\tProteobacteria\tphylum\t0.98\tGammaproteobacteria\tclass\t0.97\tOceanospirillales\torder\t0.54\tOceanospirillaceae\tfamily\t0.51\tOceanospirillum\tgenus\t0.44",
        "D27LU0R02A82DK\tRoot\troot\t1.0\tBacteria\tdomain\t1.00\tProteobacteria\tphylum\t1.00\tGammaproteobacteria\tclass\t1.00\tThiotrichales\torder\t1.00\tFrancisellaceae\tfamily\t0.63\tFrancisella\tgenus\t0.63"
    ), "sogin.unique.fix.tax")
}

if (!file.exists("sogin.names")) {
    writeLines(c(
        "D4WT9DQ06DVGFR\tD4WT9DQ06DVGFR",
        "D4WT9DQ05C6YNI\tD4WT9DQ05C6YNI",
        "D4WT9DQ12HNQY2\tD4WT9DQ12HNQY2",
        "D4WT9DQ01AP0UQ\tD4WT9DQ01AP0UQ",
        "D4WT9DQ09FLPTJ\tD4WT9DQ09FLPTJ",
        "D27LU0R02A82DK\tD27LU0R02A82DK"
    ), "sogin.names")
}

if (!file.exists("sample_metadata.txt")) {
    df <- data.frame(
        Site = c("Labrador seawater", "Oxygen minimum", "Lower deep water", "Oxygen minimum", "Labrador seawater", "Labrador seawater", "Bag City Ma"),
        Lat_N = c(58.3, 58.3, 50.4, 50.4, 60.9, 60.9, 0),
        Long_W = c(-29.133, -29.133, -25.000, -25.000, -38.516, -38.516, 0),
        Depth = c(1400, 500, 4121, 550, 1710, 710, 0),
        Temperature = c(3.5, 7.1, 2.3, 7.0, 3.0, 3.5, 0),
        Cells = c(6.4e4, 1.8e5, 3.9e4, 1.5e5, 3.3e4, 5.2e4, 0),
        row.names = c("53R", "55R", "112R", "115R", "137", "138", "FS312")
    )
    write.table(df, "sample_metadata.txt", sep="\t", quote=FALSE, col.names=NA)
}

if (!file.exists("sogin.fasta")) {
    writeLines(c(
        ">D4WT9DQ06DVGFR",
        "TGCCTTTGACATCCTCGGAACGGTGGTGCCTTCGGGAACCGAGAGAC",
        ">D4WT9DQ05C6YNI",
        "TGGACTTGACATGTTAGTGTAAACAGCTTGCTCAAAGACACTATCAC",
        ">D4WT9DQ12HNQY2",
        "CGGGCTTGAAGTGCAAGCGACAACGATTTCCGCAAGGACGCTTGTAG",
        ">D4WT9DQ01AP0UQ",
        "TGGTCTTGACATCCCGGGAATCTCCCTCATTAGAGGAGCCTGGTGAC",
        ">D4WT9DQ09FLPTJ",
        "AGGACTTGACATCCAGAGAACTCGGGTGCCTTCGGGAACTCTGTGAC",
        ">D27LU0R02A82DK",
        "ATCCCTTGACATCCTGCGAACTTTTGGTGCCTTCGGAACGCAGTGAC"
    ), "sogin.fasta")
}