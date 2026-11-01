# IH-LM architecture schematic

`method_architecture.svg` is an editable vector figure; `method_architecture.png` is its 3600 × 3080 preview. `build_architecture.py` generates both using Python/Pillow and macOS Arial fonts. It performs document rendering only, without model execution or scientific analysis.

Panels show (a) qualified typed evidence memory and separate chemical-prefix input, (b) the causal decoder, evidence cross-attention and symbolic mask, and (c) preference adaptation with separate stopping and final evaluation channels. Green denotes trainable adaptation; purple denotes evidence handling. The figure contains no measured outcomes.

## Source mapping

Sources under `research/guangzhou_all_atom/cyclic_llm/allatom_paper/`:

- `hybrid/knowledge_memory.py`: fixed raw typed memory, eligibility masks and null slot; source IDs are audit metadata rather than neural features.
- `hybrid/knowledge_projection.py`: trainable category embeddings and feature projection; frozen molecular vectors remain inputs.
- `hybrid/knowledge_attention.py` and `knowledge_decoder.py`: evidence attention after causal self-attention and before the MLP, including the residual update. Initial output projection is zero. The adapter supports the pinned Llama interface.
- `hybrid/knowledge_bridge.py`: separate policy and frozen initial reference projection/attention, both consuming identical raw memory.
- `hybrid/model.py`: chemical-prefix conditioning, Q/V LoRA, completion-only likelihood, DPO and bridge updates. The reference disables LoRA and uses the frozen evidence branch.
- `hybrid/knowledge_parent.py`: an optional parent-selection factor, distinct from learned conditioning. Its permissions do not authorize learned inputs or numeric priors.
- `hybrid/sampling.py` and `rules/constraint.py`: temperature, optional qualified soft potential, token mask and exact EOS check. Prefix admissibility does not prove successful completion.
- `hybrid/adapters.py`: separate stopping and preference-update interfaces.

Decoder notation abbreviates grouped-query heads and uses one head for the evidence-attention equation. The causal attention mask, evidence-slot mask and chemical token mask have distinct roles. Dimensions, checkpoint identities, selected layers and hyperparameters belong in experimental setup.

The diagram represents implemented capabilities, not full-size checkpoint acceptance or scientific efficacy. Off/null/on comparisons hold chemical inputs and source exclusions fixed; retrieval/parent selection is a separate factor. Optional soft potentials require their own qualified numeric evidence. No 3D coordinate generator or accepted real-source training catalogue is implied.

The PNG was visually inspected after rendering. The manuscript supplies typeset equations and full definitions.
