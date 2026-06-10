library(MetaPhOR)

brca_file <- system.file("extdata", "BRCA_DEGS.csv", package = "MetaPhOR")
if (file.exists(brca_file)) {
    file.copy(brca_file, "BRCA_DEGS.csv", overwrite = TRUE)
} else {
    brca_df <- data.frame(
        X = c("TATDN1", "ZNF706", "DCAF13", "TRMT12", "IGF2BP1", "MAP6D1"),
        logFC = c(0.0996779, 0.1055866, 0.0882855, 0.1093866, 0.9256589, 0.1619178),
        AveExpr = c(6.112478, 6.446976, 6.393943, 6.071099, 4.454204, 5.719428),
        t = c(6.074387, 5.845307, 5.513711, 5.434470, 5.631783, 5.342911),
        P.Value = c(0, 0, 1e-07, 1e-07, 0, 1e-07),
        adj.P.Val = c(0.0000523, 0.0000958, 0.0002918, 0.0003550, 0.0002065, 0.0004612),
        B = c(10.736686, 9.237467, 7.531541, 7.377948, 7.273836, 7.090578)
    )
    write.csv(brca_df, "BRCA_DEGS.csv", row.names = FALSE)
}

ovca_file <- system.file("extdata", "OVCA_Scores.csv", package = "MetaPhOR")
if (file.exists(ovca_file)) {
    file.copy(ovca_file, "OVCA_Scores.csv", overwrite = TRUE)
} else {
    ovca_df <- data.frame(
        Scores = c(0.0293332, 0.0031671, 0.2400430, 0.0314352, 0.0004634, -0.0392858),
        ABSScores = c(0.0299031, 0.0031671, 0.2614076, 0.1469312, 0.0080444, 0.1046875),
        ScorePvals = c(0.22996, 0.43074, 0.06334, 0.48340, 0.52228, 0.79502),
        ABSScorePvals = c(0.60408, 0.91878, 0.35952, 0.92848, 0.92286, 0.35816)
    )
    rownames(ovca_df) <- c("Cardiolipin.Metabolism", "Cardiolipin.Biosynthesis", 
                           "Cholesterol.Biosynthesis", "Citric.Acid.Cycle", 
                           "Cyclooxygenase.Arachidonic.Acid.Metabolism", "Prostaglandin.Biosynthesis")
    write.csv(ovca_df, "OVCA_Scores.csv", row.names = TRUE)
}

prad_file <- system.file("extdata", "PRAD_Scores.csv", package = "MetaPhOR")
if (file.exists(prad_file)) {
    file.copy(prad_file, "PRAD_Scores.csv", overwrite = TRUE)
} else {
    prad_df <- data.frame(
        Scores = c(0.0193332, 0.0131671, 0.1400430, 0.0214352, 0.0104634, -0.0292858),
        ABSScores = c(0.0199031, 0.0131671, 0.1614076, 0.1269312, 0.0180444, 0.1146875),
        ScorePvals = c(0.12996, 0.33074, 0.04334, 0.38340, 0.42228, 0.69502),
        ABSScorePvals = c(0.50408, 0.81878, 0.25952, 0.82848, 0.82286, 0.25816)
    )
    rownames(prad_df) <- c("Cardiolipin.Metabolism", "Cardiolipin.Biosynthesis", 
                           "Cholesterol.Biosynthesis", "Citric.Acid.Cycle", 
                           "Cyclooxygenase.Arachidonic.Acid.Metabolism", "Prostaglandin.Biosynthesis")
    write.csv(prad_df, "PRAD_Scores.csv", row.names = TRUE)
}