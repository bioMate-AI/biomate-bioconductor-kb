# ZINC600 top-20 purchasability / identity lookup

_Updated: 2026-06-04T20:58:02.992114+00:00_

Backends: **local_tranche, pubchem**

| Rank | Vina | ZINC ID (tranche) | PubChem CID | In tranche? | CartBlanche | SMILES |
| ---: | ---: | --- | ---: | --- | --- | --- |
| 1 | -6.527 | 38643678 | 11971027 | yes | no | `N=C(N)NC(=O)NC(=O)NC(=N)N` |
| 2 | -6.275 | 100282852 | 136890013 | yes | no | `Nc1nc(=O)c2c([nH]1)N[C@H](O)C=N2` |
| 3 | -6.267 | 33753639 | 3036436 | yes | no | `N=C(N)NC(=O)c1nccnc1N` |
| 4 | -6.099 | 39114411 | 93509744 | yes | no | `C[C@@H]1CN[C@H]2NC(N)=NC(=O)[C@@H]2N` |
| 5 | -6.065 | 33607431 | 3019440 | yes | no | `N=C(N)NC(=O)NC(=N)N` |
| 6 | -6.014 | 32203238 | 92860315 | yes | no | `O=C1Nc2c[nH]c(=O)nc2N[C@H]1O` |
| 7 | -5.933 | 8076670 | 11937742 | yes | no | `C[C@@H](O)[C@@H]1NC(=O)[C@@H]2CCCN2C` |
| 8 | -5.912 | 39114413 | 93509746 | yes | no | `C[C@@H]1CN[C@@H]2NC(N)=NC(=O)[C@@H]2` |
| 9 | -5.902 | 39126365 | 21844985 | yes | no | `CC(=O)NC1=NN(C)C(=O)C1(O)O` |
| 10 | -5.881 | 39114546 | 10702521 | yes | no | `CNC1=NC(N)=C2NCCN=C2N1` |
| 11 | -5.831 | 39114294 | 136854004 | yes | no | `NC1=NC(=O)C2=N[C@H](O)CNC2=N1` |
| 12 | -5.825 | 32203242 | 92860316 | yes | no | `O=C1Nc2c[nH]c(=O)nc2N[C@@H]1O` |
| 13 | -5.759 | 45814481 | 45099751 | yes | no | `Nc1nc(=O)[nH]c2[nH]c(=O)cnc12` |
| 14 | -5.731 | 255974859 | — | yes | no | `C[C@@H]1CN[C@H]2NC(N)=NC(=O)[C@H]2N1` |
| 15 | -5.697 | 33605916 | 3018123 | yes | no | `NC(=O)NC(=O)NC(=O)C(N)=O` |
| 16 | -5.678 | 141653894 | 136434526 | yes | no | `Nc1oc2c(N)[n+]([O-])n(O)c2c1O` |
| 17 | -5.603 | 12501434 | 7059413 | yes | no | `O=C(O)[C@@H]1O[C@H](O)[C@@H](O)[C@H]` |
| 18 | -5.599 | 2265357464 | 11789859 | yes | no | `C[C@]12NCCN3CCN(CCN1)[C@@H]32` |
| 19 | -5.567 | 197749338 | 22677571 | yes | no | `NN1NC(=O)c2[nH]cnc2N1` |
| 20 | -5.560 | 238568487 | 102602458 | yes | no | `N=C(N)C1=C[C@@H](O)[C@@H](O)[C@@H](C` |

## Notes

- **local_tranche** matches the publication library source ([AAAC.smi](https://files.docking.org/2D/AA/AAAC.smi), first 600 compounds). ZINC IDs were stripped when the library was copied; this backend restores them.
- **PubChem** confirms public compound identity; not the same as ZINC vendor catalogs.
- **CartBlanche** is optional; API availability varies by network.
