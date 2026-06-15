---
name: bioconductor-tanggle
description: Offers functions for plotting split (or implicit) networks (unrooted, undirected) and explicit networks (rooted, directed) with reticulations extending. 'ggtree' and using functions from 'ape' and 'phangorn'. It extends the 'ggtree' package [@Yu2017] to allow the visualization of phylogenetic networks using the 'ggplot2' syntax. It offers an alternative to the plot functions already available in 'ape' Paradis and Schliep (2019) <doi:10.1093/bioinformatics/bty633> and 'phangorn' Schliep (2011) <d
when_to_use: Use when: ***tanggle***: Visualization of phylogenetic networks in a *ggplot2* framework; ***tanggle***: Visualización de redes filogenéticas con *ggplot2*. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# tanggle

## Workflows

### Standard Workflow

Visualize unrooted, undirected split networks (such as consensus networks or neighbor-nets) from Nexus files.

```r
library(tanggle)
library(phangorn)
library(ggtree)

fdir <- system.file("extdata/trees", package = "phangorn")
Nnet <- phangorn::read.nexus.networx(file.path(fdir,"woodmouse.nxs"))

p <- ggsplitnet(Nnet) + geom_tiplab2()
p <- p + xlim(-0.019, .003) + ylim(-.01, .012)
```
*Input: A Nexus file containing split network data, read as a networx object; Output: A ggplot object representing the unrooted split network with tip labels.*

### Explicit Networks

Visualize explicit, rooted phylogenetic networks with reticulations from extended Newick format.

```r
library(tanggle)
library(ape)

z <- read.evonet(text = "((1,((2,(3,(4)Y#H1)g)e,(((Y#H1,5)h,6)f)X#H2)c)a, ((X#H2,7)d,8)b)r;")
p <- ggevonet(z, layout = "slanted") + geom_tiplab() + geom_nodelab()
```
*Input: An extended Newick format string; Output: A ggplot object representing a rooted phylogenetic network with reticulations.*

## When to Use
- Visualizing unrooted, undirected split networks (consensus networks or neighbor-nets) using `ggsplitnet`.
- Visualizing explicit, rooted phylogenetic networks with reticulations using `ggevonet`.
- Customizing phylogenetic network plots with `ggplot2` layers such as `geom_tiplab2` and `geom_nodepoint`.

## When NOT to Use
- For standard, non-reticulated phylogenetic trees, use `ggtree` directly as it is optimized for simple tree structures.
- For plotting networks without a phylogenetic context (e.g., protein-protein interaction networks), use `ggraph` or `igraph`.

## Data Requirements
- Split networks must be represented as a `networx` object, typically read via `phangorn::read.nexus.networx`.
- Explicit networks must be represented as an `evonet` object, typically read via `ape::read.evonet`.

## Key Parameters
- **layout** ("rectangular"): Layout style for explicit networks in `ggevonet` (can be `"rectangular"` or `"slanted"`).
- **col** ("blue"): Color parameter inside `geom_tiplab2` or `geom_nodepoint` to customize labels and nodes.
- **font** (4): Font style parameter in `geom_tiplab2`.
- **hjust** (-0.15): Horizontal adjustment for tip labels in `geom_tiplab2`.

## Best Practices
- Adjust plot limits using `xlim` and `ylim` to ensure long tip labels are fully visible and readable.
- Use `geom_tiplab2` for split networks to properly align labels along the network perimeter.
- Minimize reticulation line crossings in complex explicit networks using `minimize_overlap`.

## Common Pitfalls
- Truncated tip labels: Labels extending beyond the default plot margins. Fix by adding `xlim` and `ylim` limits to the ggplot object.
- Overlapping reticulation lines: Hard-to-read explicit networks. Fix by applying `minimize_overlap` to the network object before plotting.

## Alternatives
- `ape`: For basic plotting of `evonet` objects without `ggplot2` syntax.
- `phangorn`: For basic plotting of `networx` split networks without `ggplot2` integration.

## Citations
- Yu, Guangchuang, David Smith, Huachen Zhu, Yi Guan, and Tommy Tsan-Yuk Lam. 2017. "Ggtree: An R Package for Visualization and Annotation of Phylogenetic Trees with Their Covariates and Other Associated Data." Methods in Ecology and Evolution 8 (1): 28–36.
- Cardona, Gabriel, Francesc Rosselló, and Gabriel Valiente. 2008. "Extended Newick: It Is Time for a Standard Representation of Phylogenetic Networks." BMC Bioinformatics 9 (1): 532.

## References
- Homepage: bioconductor.org/packages/tanggle
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/tanggle/inst/doc/tanggle.html
