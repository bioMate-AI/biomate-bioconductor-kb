# ZINC600 top-5 purchasability / identity lookup

_Updated: 2026-06-05T03:27:35.785123+00:00_

Backends: **local_tranche, pubchem**

| Rank | Vina | ZINC ID (tranche) | PubChem CID | In tranche? | CartBlanche | SMILES |
| ---: | ---: | --- | ---: | --- | --- | --- |
| 1 | -6.527 | 38643678 | 11971027 | yes | no | `N=C(N)NC(=O)NC(=O)NC(=N)N` |
| 2 | -6.275 | 100282852 | 136890013 | yes | no | `Nc1nc(=O)c2c([nH]1)N[C@H](O)C=N2` |
| 3 | -6.267 | 33753639 | 3036436 | yes | no | `N=C(N)NC(=O)c1nccnc1N` |
| 4 | -6.099 | 39114411 | 93509744 | yes | no | `C[C@@H]1CN[C@H]2NC(N)=NC(=O)[C@@H]2N` |
| 5 | -6.065 | 33607431 | 3019440 | yes | no | `N=C(N)NC(=O)NC(=N)N` |

## Notes

- **local_tranche** matches the publication library source ([AAAC.smi](https://files.docking.org/2D/AA/AAAC.smi), first 600 compounds). ZINC IDs were stripped when the library was copied; this backend restores them.
- **PubChem** confirms public compound identity; not the same as ZINC vendor catalogs.
- **CartBlanche** is optional; API availability varies by network.
