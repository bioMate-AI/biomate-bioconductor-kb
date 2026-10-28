"""IH-LM: in-house hybrid, loop-native cyclic-peptide language model.  IHLM(backbone_cfg, tokenizer_cfg, modules=[M1..M5]).
All modelling code here is ours (standard transformer design, our implementation; no third-party modelling code). The SMILES atom regex is the public standard pattern (provenance: docs/20261030_IHLM_PROVENANCE.md).
Modules (switchable; each has a planted-signal and a leave-labs-out test in test_ihlm.py):
  M1 knowledge-prior channel, evidence-weighted fusion  w = n0/(n0+n)      (symbolic.FastMemory.evidence_weight; K callable e.g. kb_audit K_phys)
  M2 lab/assay offset module                            anchor-estimated hierarchical random effect b_s (closed form), labels are offset-corrected before every neural update
  M3 stereo-aware analog-retrieval cross-attention      k nearest revealed analogs (chirality-aware similarity) -> (a) cross-attention memory of analog tokens + label embedding, (b) similarity-biased analog attention read-out
  M4 edit-space head                                    edit(analog->query) in {nme_add, nme_remove, dflip, other}; closed-form conjugate-shrunk effect (literature prior) + learned residual; edit proposals
  M5 dual-memory loop interface                         fast symbolic memory written immediately; slow neural update every `slow_every` rounds; calibrated uncertainty (split-conformal + aleatoric head); verifier-aware reward head
LoopModel-compatible: score / update(mode) / fingerprint / uncertainty / propose_edits / cost."""
import os, re, sys, math, copy, time, json, hashlib
import numpy as np, torch, torch.nn as nn, torch.nn.functional as F
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "..", "v4_eval"))
from symbolic import FastMemory, edit_type, propose_edit_smiles, iso, mol, EDIT_PRIORS
from loop_model import CostMeter
from rdkit import Chem

SMILES_RE = re.compile(r"(\[[^\]]+]|Br?|Cl?|N|O|S|P|F|I|b|c|n|o|s|p|\(|\)|\.|=|#|-|\+|\\|\/|:|~|@|\?|>|\*|\$|\%[0-9]{2}|[0-9])")   # public standard atom-level SMILES pattern
SPECIALS = ["<pad>", "<bos>", "<eos>", "<unk>", "<mask>"]; PAD, BOS, EOS, UNK = 0, 1, 2, 3
TOPO = ["<topo_linear>", "<topo_ring>", "<topo_multi>", "<flag_ds>"]
EDITS = ["identical", "nme_add", "nme_remove", "dflip_D", "dflip_L", "dflip", "other"]
DEFAULT_ALPHABET = list("CNOSPFIBrclnosp()=#-+\\/:~@.*$%") + [str(i) for i in range(10)] + ["[C@H]", "[C@@H]", "[C@]", "[C@@]", "[nH]", "[NH]", "[N+]", "[O-]", "[NH+]", "[NH2+]", "[NH3+]", "Cl", "Br"]


class Tokenizer:
    """atom-level SMILES tokenizer; chirality kept (@/@@ and bracket atoms); topology tokens by graph rules (macro rings >= 8 atoms, S-S); open vocabulary: unseen tokens -> <unk>, but
    `fit(smiles_list)` adds every observed token (so a new monomer is represented, not dropped)."""
    def __init__(self, cfg=None):
        cfg = dict(cfg or {}); self.max_len = int(cfg.get("max_len", 256)); self.topology = bool(cfg.get("topology", True))
        self.itos = SPECIALS + TOPO + list(cfg.get("alphabet", DEFAULT_ALPHABET)); self.stoi = {t: i for i, t in enumerate(self.itos)}
    def fit(self, smiles_list):
        for s in smiles_list:
            for t in SMILES_RE.findall(s):
                if t not in self.stoi: self.stoi[t] = len(self.itos); self.itos.append(t)
        return self
    def topo_tokens(self, s):
        m = Chem.MolFromSmiles(s)
        if m is None: return []
        mr = [r for r in m.GetRingInfo().AtomRings() if len(r) >= 8]; out = ["<topo_linear>" if not mr else ("<topo_ring>" if len(mr) == 1 else "<topo_multi>")]
        if m.HasSubstructMatch(Chem.MolFromSmarts("[SX2]-[SX2]")): out.append("<flag_ds>")
        return out
    def encode(self, s):
        toks = (self.topo_tokens(s) if self.topology else []) + SMILES_RE.findall(s)
        return ([BOS] + [self.stoi.get(t, UNK) for t in toks] + [EOS])[: self.max_len]
    def __len__(self): return len(self.itos)


class Block(nn.Module):
    def __init__(s, d, h, causal):
        super().__init__(); s.h, s.causal = h, causal
        s.ln1 = nn.LayerNorm(d); s.qkv = nn.Linear(d, 3 * d); s.proj = nn.Linear(d, d)
        s.lnc = nn.LayerNorm(d); s.q = nn.Linear(d, d); s.kv = nn.Linear(d, 2 * d); s.cproj = nn.Linear(d, d)
        s.ln2 = nn.LayerNorm(d); s.mlp = nn.Sequential(nn.Linear(d, 4 * d), nn.GELU(), nn.Linear(4 * d, d))
    def forward(s, x, pad_mask, mem=None, mem_mask=None):
        B, T, D = x.shape; h = s.h; q, k, v = s.qkv(s.ln1(x)).view(B, T, 3, h, D // h).permute(2, 0, 3, 1, 4)
        am = pad_mask[:, None, None, :]
        if s.causal: am = am & torch.tril(torch.ones(T, T, dtype=torch.bool, device=x.device))[None, None]
        x = x + s.proj(F.scaled_dot_product_attention(q, k, v, attn_mask=am).transpose(1, 2).reshape(B, T, D))
        if mem is not None:
            qc = s.q(s.lnc(x)).view(B, T, h, D // h).transpose(1, 2); kc, vc = s.kv(mem).view(B, mem.shape[1], 2, h, D // h).permute(2, 0, 3, 1, 4)
            x = x + s.cproj(F.scaled_dot_product_attention(qc, kc, vc, attn_mask=mem_mask[:, None, None, :]).transpose(1, 2).reshape(B, T, D))
        return x + s.mlp(s.ln2(x))


class Backbone(nn.Module):
    """configurable standard transformer: kind 'encoder' (bidirectional) or 'decoder' (causal); optional cross-attention to an external memory."""
    def __init__(s, vocab, d=128, layers=4, heads=4, max_len=256, kind="encoder"):
        super().__init__(); s.d, s.max_len = d, max_len; s.tok = nn.Embedding(vocab, d); s.pos = nn.Embedding(max_len, d)
        s.blocks = nn.ModuleList([Block(d, heads, kind == "decoder") for _ in range(layers)]); s.ln = nn.LayerNorm(d); s.lm_head = nn.Linear(d, vocab, bias=False); s.lm_head.weight = s.tok.weight
    def embed(s, X): return s.tok(X) + s.pos(torch.arange(X.shape[1], device=X.device))[None]
    def forward(s, X, mem=None, mem_mask=None):
        pm = X != PAD; h = s.embed(X)
        for b in s.blocks: h = b(h, pm, mem, mem_mask)
        return s.ln(h), pm


def masked_mean(h, m): m = m.float()[:, :, None]; return (h * m).sum(1) / m.sum(1).clamp(min=1)


class Net(nn.Module):
    def __init__(s, vocab, cfg, modules, n_verif=1):
        super().__init__(); s.modules_on = set(modules); d = cfg["d"]; s.bb = Backbone(vocab, d, cfg.get("layers", 4), cfg.get("heads", 4), cfg.get("max_len", 256), cfg.get("kind", "encoder"))
        s.score_head = nn.Linear(d, 1); s.logvar_head = nn.Linear(d, 1); s.verif_head = nn.Linear(d, n_verif)
        s.label_proj = nn.Linear(1, d); s.wq = nn.Linear(d, d); s.wk = nn.Linear(d, d); s.gamma = nn.Parameter(torch.tensor(3.0)); s.gate = nn.Linear(2, 1)
        s.edit_res = nn.Sequential(nn.Linear(d + len(EDITS), d), nn.GELU(), nn.Linear(d, 1)); nn.init.zeros_(s.edit_res[2].weight); nn.init.zeros_(s.edit_res[2].bias)
        s.d = d

    def forward(s, X, an=None):
        """X (B,T); an = dict(ids (B,K,L), y (B,K), sim (B,K), edit (B,K), dsym (B,K), valid (B,K)) or None."""
        mem = mm = None
        if an is not None and "M3" in s.modules_on:
            B, K, L = an["ids"].shape; ids = an["ids"].reshape(B, K * L); e = s.bb.embed(an["ids"].reshape(B * K, L)).reshape(B, K * L, s.d)
            e = e + s.label_proj(an["y"][:, :, None].expand(B, K, L).reshape(B, K * L, 1)); mem = e
            mm = (ids != PAD) & an["valid"][:, :, None].expand(B, K, L).reshape(B, K * L)
            mm = torch.cat([mm, torch.ones(B, 1, dtype=torch.bool, device=X.device)], 1); mem = torch.cat([mem, torch.zeros(B, 1, s.d, device=X.device)], 1)   # always one attendable slot
        h, pm = s.bb(X, mem, mm); hp = masked_mean(h, pm); base = s.score_head(hp)[:, 0]; lv = s.logvar_head(hp)[:, 0].clamp(-6, 4); vf = s.verif_head(hp)
        out = dict(base=base, y=base, logvar=lv, verif=vf, readout=None, alpha=None)
        if an is not None and "M3" in s.modules_on:
            B, K, L = an["ids"].shape; qv = masked_mean(s.bb.tok(X), pm); av = masked_mean(s.bb.tok(an["ids"].reshape(B * K, L)), an["ids"].reshape(B * K, L) != PAD).reshape(B, K, s.d)
            att = (s.wq(qv)[:, None, :] * s.wk(av)).sum(-1) / math.sqrt(s.d) + s.gamma * an["sim"]; att = att.masked_fill(~an["valid"], -1e9); a = torch.softmax(att, 1) * an["valid"].float()
            a = a / a.sum(1, keepdim=True).clamp(min=1e-9)
            delta = an["dsym"]
            if "M4" in s.modules_on:
                oh = F.one_hot(an["edit"], len(EDITS)).float(); delta = delta + s.edit_res(torch.cat([qv[:, None, :].expand(B, K, s.d) - av, oh], -1))[..., 0]
            r = (a * (an["y"] + delta)).sum(1); nvalid = an["valid"].float().sum(1) / an["valid"].shape[1]; smax = (an["sim"] * an["valid"].float()).max(1).values
            g = torch.sigmoid(s.gate(torch.stack([smax, nvalid], -1))[:, 0]); out.update(y=(1 - g) * base + g * r, readout=r, alpha=a, gate=g)
        return out


class IHLM:
    def __init__(self, backbone_cfg=None, tokenizer_cfg=None, modules=("M1", "M2", "M3", "M4", "M5"), knowledge=None, n0=100.0, k=5, slow_every=3, alpha=0.2, eta=1.0, seed=0, n_verif=1, train_cfg=None, reference_mode=None, _clone=None):
        self.backbone_cfg = dict(dict(d=64, layers=2, heads=4, max_len=192, kind="encoder"), **(backbone_cfg or {})); self.tokenizer_cfg = dict(tokenizer_cfg or {}); self.modules = tuple(modules)
        self.reference_mode = reference_mode      # None | 'retrieval_only' | 'offset_only': no-LM reference variants through the same interface (no net is ever created or trained)
        self.knowledge, self.k, self.slow_every, self.alpha, self.eta, self.seed, self.n_verif = knowledge, int(k), int(slow_every), float(alpha), float(eta), seed, n_verif
        self.train_cfg = dict(dict(steps=150, lr=2e-3, bs=32, rank_w=0.3, verif_w=1.0), **(train_cfg or {}))
        layers = [x for x, m in (("K", "M1"), ("offset", "M2"), ("retrieval", "M3"), ("edit", "M4")) if m in self.modules]
        if _clone is None:
            self.tok = Tokenizer(self.tokenizer_cfg); torch.manual_seed(seed); self.net = None; self.net_trained = False
            self.mem = FastMemory(n0=n0, k=k, layers=layers); self.rounds_since_slow = 0; self.cal = None; self.meter = CostMeter(0); self.fast_seconds = 0.0; self.history = []
            self.provenance = {"backbone_init": "scratch", "backbone_code": "ours (ihlm/model.py)", "weights": None}
        else: self.__dict__.update(_clone)

    # ------------------------------------------------------------------ construction helpers
    def _ensure_net(self):
        if self.net is None:
            torch.manual_seed(self.seed); self.net = Net(len(self.tok), self.backbone_cfg, self.modules, self.n_verif); self.meter.n_params = sum(p.numel() for p in self.net.parameters())

    def init_backbone_from(self, state_dict, name_map=None, source="", licence="", note=""):
        """backbone init from open weights where shapes match (disclosed + licence-noticed). Returns (n_loaded, n_skipped). Design hook: PeptideCLM-2 mapping is not provided yet."""
        self._ensure_net(); own = self.net.bb.state_dict(); loaded = skipped = 0; nm = name_map or {}
        for k, v in state_dict.items():
            k2 = nm.get(k, k)
            if k2 in own and own[k2].shape == v.shape: own[k2].copy_(v); loaded += 1
            else: skipped += 1
        self.provenance = {"backbone_init": "open_weights", "source": source, "licence": licence, "note": note, "tensors_loaded": loaded, "tensors_skipped": skipped}; return loaded, skipped

    # ------------------------------------------------------------------ analog packs (M3)
    def _pack(self, queries, targets, exclude_self):
        B = len(queries); K = self.k; L = min(self.backbone_cfg["max_len"], 64); ids = torch.zeros(B, K, L, dtype=torch.long); y = torch.zeros(B, K); sim = torch.zeros(B, K); ed = torch.zeros(B, K, dtype=torch.long); ds = torch.zeros(B, K); valid = torch.zeros(B, K, dtype=torch.bool)
        for b, (q, t) in enumerate(zip(queries, targets)):
            for j, (sm, r) in enumerate(self.mem.neighbours(q, t, K, exclude_self)):
                a = self.tok.encode(r["smiles"])[:L]; ids[b, j, :len(a)] = torch.tensor(a); y[b, j] = self.mem.corrected(r); sim[b, j] = sm; valid[b, j] = True
                et, dl = self.mem.edit_delta(q, r["smiles"]); ed[b, j] = EDITS.index(et) if et in EDITS else EDITS.index("other"); ds[b, j] = dl if "M4" in self.modules else 0.0
        return dict(ids=ids, y=y, sim=sim, edit=ed, dsym=ds, valid=valid)

    def _batch(self, smiles):
        enc = [self.tok.encode(s) for s in smiles]; mx = max(len(e) for e in enc); X = torch.zeros(len(enc), mx, dtype=torch.long)
        for i, e in enumerate(enc): X[i, :len(e)] = torch.tensor(e)
        return X

    # ------------------------------------------------------------------ scoring / prediction
    def net_predict(self, smiles, target_seq=None, exclude_self=False, use_analogs=True):
        if not self.net_trained: return None
        self.net.eval(); out = {k: [] for k in ("y", "logvar", "verif")}
        with torch.no_grad():
            for i in range(0, len(smiles), 64):
                ch = smiles[i:i + 64]; X = self._batch(ch); an = self._pack(ch, [target_seq] * len(ch), exclude_self) if (use_analogs and "M3" in self.modules and self.mem.rows) else None
                o = self.net(X, an); out["y"] += o["y"].tolist(); out["logvar"] += o["logvar"].tolist(); out["verif"] += torch.sigmoid(o["verif"][:, 0]).tolist()
        self.meter.score_tokens += 2 * sum(len(self.tok.encode(s)) for s in smiles); return out

    def _K(self, smiles):
        """knowledge channel: callable(smiles_list) -> sequence of floats (None/NaN = no value)."""
        if self.knowledge is None: return [None] * len(smiles)
        out = self.knowledge(list(smiles)); return [None if (v is None or (isinstance(v, float) and np.isnan(v))) else float(v) for v in out]

    def _src_list(self, sources, n):
        if sources is None or isinstance(sources, str): return [sources] * n
        return list(sources)

    def score(self, smiles, target_seq=None, sources=None, components=("net", "K", "retrieval")):
        """ranking score (higher better) = (1-w) z(net) + w z(K) + smax * z(symbolic retrieval); None when no component can score. w = n0/(n0+n) (M1)."""
        if self.reference_mode == "retrieval_only": components = ("retrieval",)
        elif self.reference_mode == "offset_only": components = ()
        t0 = time.time(); n = len(self.mem.rows); comp = np.zeros(len(smiles)); have = np.zeros(len(smiles), bool); w = self.mem.evidence_weight(n)
        if self.reference_mode == "offset_only": have[:] = True      # ranks by lab offset only (all-equal within a source)
        z = lambda v: (np.asarray(v, float) - np.mean(v)) / (np.std(v) if np.std(v) > 0 else 1.0)
        npred = self.net_predict(smiles, target_seq) if "net" in components else None
        if npred is not None: comp[:] = (1 - w) * z(npred["y"]) if "K" in components and self.knowledge is not None and "M1" in self.modules else z(npred["y"]); have[:] = True
        if "K" in components and "M1" in self.modules and self.knowledge is not None:
            kv = self._K(smiles); ok = [i for i, v in enumerate(kv) if v is not None]
            if ok: kz = np.zeros(len(smiles)); kz[ok] = z([kv[i] for i in ok]); comp = comp + w * kz; have[ok] = True
        if "retrieval" in components and ("M3" in self.modules or self.reference_mode == "retrieval_only") and self.mem.rows:
            est = [self.mem.retrieval(s, target_seq) for s in smiles]; ok = [i for i, e in enumerate(est) if e[0] is not None]
            if ok: rz = np.zeros(len(smiles)); rz[ok] = z([est[i][0] for i in ok]); sm = np.zeros(len(smiles)); sm[ok] = [est[i][1] for i in ok]; comp = comp + sm * rz; have[ok] = True
        if "M2" in self.modules and sources is not None and self.mem.offsets:       # lab/assay offset in unit-free score space: b_s / sd of corrected revealed labels
            sd = float(np.std([self.mem.corrected(r) for r in self.mem.rows])) if len(self.mem.rows) > 2 else 1.0; sd = sd if sd > 0 else 1.0
            comp = comp + np.array([self.mem.offsets.get(s, 0.0) / sd for s in self._src_list(sources, len(smiles))])
        self.fast_seconds += time.time() - t0; return [float(c) if h else None for c, h in zip(comp, have)]

    @property
    def offsets(self): return dict(self.mem.offsets)

    def source_counts(self): return self.mem.source_counts()

    def predict_std(self, smiles, target_seq=None, sources=None):
        """array of calibrated half-widths (label units); NaN where unavailable (net untrained or n < 24)."""
        u = self.uncertainty(smiles, target_seq, sources=sources); return np.array([np.nan if x is None else x["half_width"] for x in u])

    def uncertainty(self, smiles, target_seq=None, sources=None, source=None):
        """calibrated label-unit prediction: dict(mean, lo, hi, half_width, aleatoric_std, p_pass); None if the net is untrained or calibration unavailable (n < 24)."""
        npred = self.net_predict(smiles, target_seq, use_analogs=True); srcs = self._src_list(sources if sources is not None else source, len(smiles)); res = []
        for i, s in enumerate(smiles):
            b = self.mem.offsets.get(srcs[i], 0.0) if "M2" in self.modules else 0.0
            if npred is None or self.cal is None: res.append(None); continue
            smax = self.mem.retrieval(s, target_seq)[1] if self.mem.rows else 0.0; hw = self.cal["q"] * (1.0 + self.eta * (1 - smax)); m = npred["y"][i] + b
            res.append(dict(mean=float(m), lo=float(m - hw), hi=float(m + hw), half_width=float(hw), aleatoric_std=float(math.exp(0.5 * npred["logvar"][i])), p_pass=float(npred["verif"][i])))
        return res

    def reward(self, smiles, target_seq=None, source=None, kappa=0.0):
        """verifier-aware reward: (mean + kappa*half_width) * P(pass verifiers); unscorable -> -inf."""
        u = self.uncertainty(smiles, target_seq, source); return [(-np.inf if x is None else (x["mean"] + kappa * x["half_width"]) * x["p_pass"]) for x in u]

    def propose_edits(self, smiles, target_seq=None, source=None, n=5, kappa=1.0):
        """M4: enumerate single edits of a measured parent (N-Me add/remove, D-flip), score each (label units + closed-form edit prior), rank by UCB. -> list of dict."""
        cands = propose_edit_smiles(smiles); res = []
        if not cands: return res
        u = self.uncertainty([c[1] for c in cands], target_seq, source)
        for (et, s), x in zip(cands, u):
            prior = self.mem.edit_eff.get(et, 0.0)
            if x is None: res.append(dict(edit=et, smiles=s, prior_effect=prior, ucb=prior, mean=None))
            else: res.append(dict(edit=et, smiles=s, prior_effect=prior, mean=x["mean"], half_width=x["half_width"], ucb=x["mean"] + kappa * x["half_width"]))
        res.sort(key=lambda r: -r["ucb"]); return res[:n]

    # ------------------------------------------------------------------ M5: dual-memory update
    def clone(self):
        c = IHLM.__new__(IHLM); d = {k: v for k, v in self.__dict__.items()}
        d["mem"] = self.mem.clone(); d["meter"] = copy.deepcopy(self.meter); d["history"] = list(self.history); d["net"] = copy.deepcopy(self.net) if self.net is not None else None; d["cal"] = copy.deepcopy(self.cal); c.__dict__.update(d); return c

    def update(self, labelled, mode="finetune_ranking", seed=0, **kw):
        """labelled: [{smiles, target_seq, label, source?, verifier?}] (higher = better). frozen: unchanged. Otherwise the FAST symbolic memory is written immediately (offsets, edit effects,
        analog index, evidence weight); the SLOW neural memory is updated every `slow_every` rounds (or at once for one_shot_matched)."""
        new = self.clone(); new.history.append((mode, len(labelled), seed))
        if mode == "frozen": return new
        t0 = time.time(); new.tok.fit([r["smiles"] for r in labelled])
        if "M1" in new.modules and new.knowledge is not None:
            kk = new._K([r["smiles"] for r in labelled]); labelled = [dict(r, K=k) for r, k in zip(labelled, kk)]
        new.mem.write(labelled)
        for r in labelled:
            if r.get("verifier") is not None:
                for row in new.mem.rows:
                    if row["smiles"] == iso(r["smiles"]) and row["source"] == r.get("source"): row["verifier"] = float(r["verifier"])
        new.fast_seconds += time.time() - t0; new.rounds_since_slow += 1
        if new.reference_mode is not None: return new                  # reference variants: fast memory only, never a neural update
        if mode == "one_shot_matched" or new.rounds_since_slow >= new.slow_every: new._slow_fit(seed, rounds=kw.get("rounds", 1), mode=mode, steps=kw.get("steps")); new.rounds_since_slow = 0
        return new

    def _slow_fit(self, seed, rounds=1, mode="finetune_ranking", steps=None):
        rows = self.mem.rows
        if len(rows) < 8: return
        t0 = time.time(); self._ensure_net(); cfg = self.train_cfg; steps = int(steps if steps is not None else cfg["steps"]) * (max(1, int(rounds)) if mode == "one_shot_matched" else 1)
        h = [int(hashlib.sha256(f"{self.seed}|{r['smiles']}|{r['source']}".encode()).hexdigest(), 16) % 2 for r in rows]
        use_cal = len(rows) >= 24; fit_idx = [i for i, hh in enumerate(h) if hh == 0] if use_cal else list(range(len(rows))); cal_idx = [i for i, hh in enumerate(h) if hh == 1] if use_cal else []
        smi = [r["smiles"] for r in rows]; tgt = [r["target_seq"] for r in rows]; X_all = self._batch(smi); an_all = self._pack(smi, tgt, True) if ("M3" in self.modules) else None
        y_all = torch.tensor([self.mem.corrected(r) for r in rows], dtype=torch.float32); ver = [r.get("verifier") for r in rows]
        tid = {t: i for i, t in enumerate(sorted(set(tgt), key=str))}; tg = torch.tensor([tid[t] for t in tgt])
        torch.manual_seed(int(seed)); rng = np.random.default_rng(int(seed)); self.net.train(); train_params = self.layernorm_parameters() if mode == "layernorm_peft" else list(self.net.parameters())
        for q in self.net.parameters(): q.requires_grad_(any(q is z for z in train_params))
        opt = torch.optim.AdamW(train_params, lr=cfg["lr"], weight_decay=0.0)
        for _ in range(steps):
            idx = torch.tensor(rng.choice(fit_idx, min(cfg["bs"], len(fit_idx)), replace=False)); an = {k: v[idx] for k, v in an_all.items()} if an_all is not None else None
            o = self.net(X_all[idx], an); y = y_all[idx]; nll = (0.5 * (torch.exp(-o["logvar"]) * (y - o["y"]) ** 2 + o["logvar"])).mean(); loss = nll
            d = (y[:, None] - y[None, :]); same = tg[idx][:, None] == tg[idx][None, :]; pair = (d > 0) & same
            if pair.any(): s_ = o["y"]; loss = loss + cfg["rank_w"] * (-F.logsigmoid((s_[:, None] - s_[None, :])[pair])).mean()
            vm = torch.tensor([ver[int(i)] is not None for i in idx])
            if vm.any(): vt = torch.tensor([float(ver[int(i)]) for i in idx if ver[int(i)] is not None]); loss = loss + cfg["verif_w"] * F.binary_cross_entropy_with_logits(o["verif"][vm][:, 0], vt)
            opt.zero_grad(); loss.backward(); torch.nn.utils.clip_grad_norm_(self.net.parameters(), 1.0); opt.step(); self.meter.train_tokens += 2 * int(X_all[idx].numel())
        for q in self.net.parameters(): q.requires_grad_(True)
        self.net.eval(); self.net_trained = True; self.meter.updates += 1; self.meter.update_seconds += time.time() - t0
        self.cal = None
        if use_cal and len(cal_idx) >= 6:      # split-conformal on the held-aside half (net never trained on these rows' losses)
            ci = torch.tensor(cal_idx); an = {k: v[ci] for k, v in an_all.items()} if an_all is not None else None
            with torch.no_grad(): o = self.net(X_all[ci], an)
            smax = (an["sim"] * an["valid"].float()).max(1).values.numpy() if an is not None else np.zeros(len(cal_idx)); res = (y_all[ci] - o["y"]).abs().numpy() / (1.0 + self.eta * (1 - smax))
            self.cal = dict(q=float(np.quantile(res, min(1.0, math.ceil((len(res) + 1) * (1 - self.alpha)) / len(res)))), n_cal=len(res))

    def layernorm_parameters(self):
        """all LayerNorm parameters of the net (for LayerNorm-only PEFT); [] before the net exists."""
        self._ensure_net(); return [p for m in self.net.modules() if isinstance(m, nn.LayerNorm) for p in m.parameters()]

    # ------------------------------------------------------------------ interface parity
    def fingerprint(self):
        h = hashlib.sha256(self.mem.digest().encode())
        if self.net is not None:
            for k, v in sorted(self.net.state_dict().items()): h.update(k.encode()); h.update(v.detach().cpu().numpy().tobytes())
        return h.hexdigest()[:16]

    def cost(self, usd_per_hour=0.35):
        r = self.meter.report(usd_per_hour); r.update(fast_memory_seconds=round(self.fast_seconds, 3), modules=list(self.modules), provenance=self.provenance); return r
