library(tanggle)
library(phangorn)
library(ggtree)
library(ape)

# From the vignette:
# Importar una red explícita (ejemplo de Fig. 2 en Cardona et al. 2008):
network_string <- "((1,((2,(3,(4)Y#H1)g)e,(((Y#H1,5)h,6)f)X#H2)c)a, ((X#H2,7)d,8)b)r;"

# Write to the expected input file
writeLines(network_string, "network_text")