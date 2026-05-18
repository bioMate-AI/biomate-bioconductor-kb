"""CryoEnsemble — per-particle cryo-EM image likelihood for conformational posteriors.

Modules
-------
forward_model : Differentiable atom-to-image rendering (Cα → density → projection → CTF)
likelihood    : Per-particle Gaussian log-likelihood
ctf           : Contrast transfer function
poses         : Particle pose parsing (cryoDRGN, RELION star)
dps           : Diffusion posterior sampler (gradient through likelihood)
"""

__version__ = "0.1.0"
