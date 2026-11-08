"""Features, nulls, models and the domain splitter.  Everything takes an explicit train frame and test frame;
the splitter guarantees no test domain appears in training."""
import numpy as np, pandas as pd
from sklearn.linear_model import Ridge, LinearRegression
from sklearn.ensemble import HistGradientBoostingRegressor
from common import AAS, KD, CHARGE, VOL, AROM, DOMAINS, RAW

MAXL = 14
FAMS = sorted(DOMAINS)
AA_IDX = {a: i for i, a in enumerate(AAS)}


# ------------------------------------------------------------------ splitter
def lodo_split(df, test_domain, train_domains=None, max_identity=None, ident=None, only_class=None):
    """Return (train, test). Test = rows of `test_domain`; train = rows of other domains only."""
    train_dom = [d for d in sorted(df.domain.unique()) if d != test_domain]
    if train_domains is not None:
        train_dom = [d for d in train_domains if d != test_domain]
    if max_identity is not None:
        train_dom = [d for d in train_dom if ident[test_domain][d] <= max_identity]
    if only_class is not None:
        train_dom = [d for d in train_dom if DOMAINS[d]["cls"] == only_class]
    tr = df[df.domain.isin(train_dom)]
    te = df[df.domain == test_domain]
    assert test_domain not in set(tr.domain), "domain leakage"
    return tr, te


# ------------------------------------------------------------------ features
def _phys(seq, bb):
    h = np.mean([KD[a] for a in seq]); c = sum(CHARGE[a] for a in seq)
    ar = sum(a in AROM for a in seq)
    dh = dv = dc = 0.0; nm = 0
    if len(seq) == len(bb):
        for a, b in zip(seq, bb):
            if a != b:
                nm += 1; dh += KD[a] - KD[b]; dv += VOL[a] - VOL[b]; dc += CHARGE[a] - CHARGE[b]
    return [h, c, ar, nm, dh, dv / 100.0, dc]


PHYS_N = 7


def peptide_features(df):
    """Returns (cat, phys): cat = C-terminus aligned residue index per position (-1 = absent), phys = 7 physchem."""
    cat = -np.ones((len(df), MAXL), int)
    phys = np.zeros((len(df), PHYS_N))
    for r, (s, bb) in enumerate(zip(df.aa_seq.values, df.backbone.values)):
        for i, a in enumerate(s):
            cat[r, len(s) - 1 - i] = AA_IDX[a]
        phys[r] = _phys(s, bb)
    return cat, phys


def onehot(cat):
    X = np.zeros((cat.shape[0], MAXL * 20))
    for j in range(MAXL):
        ok = cat[:, j] >= 0
        X[np.where(ok)[0], j * 20 + cat[ok, j]] = 1
    return X


def fam_oh(df):
    X = np.zeros((len(df), len(FAMS)))
    for i, f in enumerate(df.family.values):
        X[i, FAMS.index(f)] = 1
    return X


def dom_oh(df, doms):
    X = np.zeros((len(df), len(doms)))
    for i, d in enumerate(df.domain.values):
        if d in doms:
            X[i, doms.index(d)] = 1
    return X


class Feat:
    """Standardiser for physchem fit on train only."""
    def __init__(self, tr):
        _, p = peptide_features(tr)
        self.mu, self.sd = p.mean(0), p.std(0) + 1e-9

    def pos(self, df):
        return onehot(peptide_features(df)[0])

    def phys(self, df):
        return (peptide_features(df)[1] - self.mu) / self.sd

    def full(self, df, fam=True):
        parts = [self.pos(df), self.phys(df)]
        if fam:
            parts.append(fam_oh(df))
        return np.hstack(parts)


# ------------------------------------------------------------------ domain side information
def domain_descriptors():
    rows = {}
    for d, v in DOMAINS.items():
        s = v["seq"]
        rows[d] = [np.mean([KD[a] for a in s]), sum(CHARGE[a] for a in s) / len(s) * 10, len(s) / 100,
                   sum(a in AROM for a in s) / len(s), sum(a in "GP" for a in s) / len(s), 1.0 if v["cls"] == "SH3" else 0.0]
    return rows


def blosum_similarity():
    """Normalised BLOSUM62 global alignment score and percent identity between the domain sequences."""
    from Bio import Align
    from Bio.Align import substitution_matrices
    al = Align.PairwiseAligner(); al.substitution_matrix = substitution_matrices.load("BLOSUM62")
    al.open_gap_score = -10; al.extend_gap_score = -0.5; al.mode = "global"
    ids = list(DOMAINS)
    sc = {a: {b: al.score(DOMAINS[a]["seq"], DOMAINS[b]["seq"]) for b in ids} for a in ids}
    sim = {a: {b: sc[a][b] / np.sqrt(sc[a][a] * sc[b][b]) for b in ids} for a in ids}
    ident = {a: {} for a in ids}
    for a in ids:
        for b in ids:
            if a == b:
                ident[a][b] = 1.0; continue
            aln = al.align(DOMAINS[a]["seq"], DOMAINS[b]["seq"])[0]
            m = 0
            for (s1, e1), (s2, e2) in zip(*aln.aligned):
                m += sum(x == y for x, y in zip(DOMAINS[a]["seq"][s1:e1], DOMAINS[b]["seq"][s2:e2]))
            ident[a][b] = m / min(len(DOMAINS[a]["seq"]), len(DOMAINS[b]["seq"]))
    return sim, ident


# ------------------------------------------------------------------ nulls
def null_promiscuity(tr, te):
    m = tr.groupby("aa_seq").score.mean()
    return te.aa_seq.map(m).values.astype(float)


def null_additive_position(tr, te, alpha=10.0):
    f = Feat(tr); preds = []
    Xte = f.pos(te)
    for d, g in tr.groupby("domain"):
        r = Ridge(alpha=alpha).fit(f.pos(g), g.score.values)
        preds.append(r.predict(Xte))
    return np.mean(preds, 0)


def null_physchem(tr, te, alpha=10.0):
    f = Feat(tr)
    r = Ridge(alpha=alpha).fit(f.phys(tr), tr.score.values)
    return r.predict(f.phys(te))


def pwm_scores(te):
    return te.pwm.values.astype(float)


# ------------------------------------------------------------------ models
def model_additive_offsets(tr, te, alpha=10.0):
    """(i) pooled additive position model with domain and family offsets (domain offset = train average at test)."""
    f = Feat(tr); doms = sorted(tr.domain.unique())
    X = np.hstack([f.full(tr), dom_oh(tr, doms)])
    r = Ridge(alpha=alpha).fit(X, tr.score.values)
    Xt = np.hstack([f.full(te), np.tile(np.ones(len(doms)) / len(doms), (len(te), 1))])
    return r.predict(Xt)


def model_lowrank(tr, te, sim, alpha=10.0, rank=2, tau=0.1):
    """(ii) low-rank factorisation of per-domain weight matrix; test-domain weights = similarity-kernel mixture."""
    f = Feat(tr); doms = sorted(tr.domain.unique())
    W, B = [], []
    for d in doms:
        g = tr[tr.domain == d]
        r = Ridge(alpha=alpha).fit(f.full(g), g.score.values)
        W.append(r.coef_); B.append(r.intercept_)
    W = np.array(W); B = np.array(B)
    mu = W.mean(0); C = W - mu
    k = min(rank, len(doms) - 1)
    if k >= 1:
        U, S, Vt = np.linalg.svd(C, full_matrices=False)
        Wr = mu + (U[:, :k] * S[:k]) @ Vt[:k]
    else:
        Wr = W
    td = te.domain.iloc[0]
    s = np.array([sim[td][d] for d in doms]) / tau
    w = np.exp(s - s.max()); w /= w.sum()
    wt = w @ Wr; bt = w @ B
    return f.full(te) @ wt + bt


def model_gbm(tr, te, desc, seed=0):
    """(iii) gradient boosting on peptide x domain features."""
    f = Feat(tr)
    def X(df):
        cat, _ = peptide_features(df)
        dd = np.array([desc[d] for d in df.domain.values])
        return np.hstack([cat.astype(float), f.phys(df), fam_oh(df), dd])
    cat_mask = [True] * MAXL + [False] * (PHYS_N + len(FAMS) + 6)
    m = HistGradientBoostingRegressor(max_depth=3, max_iter=200, learning_rate=0.05, random_state=seed,
                                      categorical_features=cat_mask)
    Xtr = X(tr); Xte = X(te)
    # absent positions are encoded as category 20 (sklearn categoricals must be non-negative)
    for A in (Xtr, Xte):
        sub = A[:, :MAXL]; sub[sub < 0] = 20
    m.fit(Xtr, tr.score.values)
    return m.predict(Xte)
