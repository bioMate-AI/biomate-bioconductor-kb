"""Measured H1-H4 task losses; independent of annotation/clinical proxies.

Inputs must already be on explicitly documented comparable scales. In particular
H4 delta is a paired log-abundance change, not detection classification. Censored
absolute log abundance is a distinct likelihood with a known assay threshold.
"""
import torch
from torch.nn import functional as F

CONTINUOUS = {"h1_transcription_delta", "h2_translation_efficiency",
              "h3_protein_delta", "h4_presentation_delta"}
SUPPORTED = CONTINUOUS | {"h4_log_abundance", "ms_detectability", "class2_register"}


def observed_values(prediction, target, mask):
    if mask.dtype != torch.bool or prediction.shape != target.shape or mask.shape != target.shape:
        raise ValueError("Prediction, measurement and boolean observation mask must align")
    if not mask.any():
        raise ValueError("No observed measurements for scheduled objective")
    p, y = prediction[mask], target[mask]
    if not torch.isfinite(p).all() or not torch.isfinite(y).all():
        raise ValueError("Nonfinite observed prediction/measurement")
    return p, y


def censored_normal_nll(mean, log_scale, target, observed, censored, limit):
    """Left-censored Gaussian likelihood on a declared log-abundance scale.

    observed: quantified values; censored: known below an assay limit. Unknown
    entries have both masks false. A missing peptide without a justified limit
    cannot be assigned censored=true by this loss.
    """
    shape = mean.shape
    if any(x.shape != shape for x in (log_scale, target, observed, censored, limit)):
        raise ValueError("Censoring tensors must align")
    if observed.dtype != torch.bool or censored.dtype != torch.bool or (observed & censored).any():
        raise ValueError("Quantified and censored masks must be disjoint booleans")
    active = observed | censored
    if not active.any():
        raise ValueError("No abundance likelihood observations")
    if not torch.isfinite(mean[active]).all() or not torch.isfinite(log_scale[active]).all():
        raise ValueError("Nonfinite likelihood parameters")
    terms = []
    if observed.any():
        p, y = observed_values(mean, target, observed)
        ls = log_scale[observed]
        terms.append(0.5 * ((y-p) * torch.exp(-ls)).square() + ls + 0.5*1.8378770664093453)
    if censored.any():
        if not torch.isfinite(limit[censored]).all():
            raise ValueError("Censored values require finite assay limits")
        z = (limit[censored] - mean[censored]) * torch.exp(-log_scale[censored])
        terms.append(-torch.special.log_ndtr(z))
    result = torch.cat(terms).mean()
    if not torch.isfinite(result):
        raise ValueError("Nonfinite abundance likelihood")
    return result


def task_loss(name, prediction, labels):
    if name not in SUPPORTED:
        raise ValueError(f"Not a canonical measured head objective: {name}")
    if name == "h4_log_abundance":
        return censored_normal_nll(prediction["mean"], prediction["log_scale"],
            labels["value"], labels["observed"], labels["censored"], labels["limit"])
    if name == "class2_register":
        y, m = labels["value"], labels["observed"]
        if y.dtype != torch.long or m.dtype != torch.bool or m.shape != y.shape or prediction.shape[:-1] != y.shape:
            raise ValueError("Register labels require aligned int64 labels and boolean masks")
        if not m.any() or not torch.isfinite(prediction[m]).all():
            raise ValueError("Missing/invalid observed register predictions")
        return F.cross_entropy(prediction[m], y[m])
    p, y = observed_values(prediction, labels["value"], labels["observed"])
    if name == "ms_detectability":
        if ((y < 0) | (y > 1)).any():
            raise ValueError("Detectability labels must lie in [0,1]")
        return F.binary_cross_entropy_with_logits(p, y)
    return F.mse_loss(p, y)
