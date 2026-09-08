# Kubernetes notes — BioNeMo NIM stack

The compose file (`docker-compose.bionemo.yml`) is the single-host reference.
For a real fleet, run each NIM as its own K8s Deployment on a GPU node pool.
This is a **sketch**, not a shipped manifest — adapt image paths/tags (confirm on
NGC) and resource sizing (see the runbook VRAM table) before applying.

## Prereqs

- A GPU node pool (EKS: managed node group of `p4d`/`p5`/`g5` with the NVIDIA
  device plugin daemonset installed — `nvidia.com/gpu` schedulable).
- An image-pull secret for `nvcr.io`:

  ```bash
  kubectl create secret docker-registry ngc-nvcr \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password="$NGC_API_KEY" \
    -n bionemo
  ```

- The runtime NGC key as a secret for weight download:

  ```bash
  kubectl create secret generic ngc-api-key \
    --from-literal=NGC_API_KEY="$NGC_API_KEY" -n bionemo
  ```

## Per-model Deployment (Boltz-2 example)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nim-boltz2
  namespace: bionemo
spec:
  replicas: 1
  selector: { matchLabels: { app: nim-boltz2 } }
  template:
    metadata: { labels: { app: nim-boltz2 } }
    spec:
      imagePullSecrets:
        - name: ngc-nvcr
      containers:
        - name: boltz2
          # CONFIRM path + tag on the NGC catalog before applying.
          image: nvcr.io/nim/mit/boltz2:PLACEHOLDER_CONFIRM_ON_NGC
          ports: [{ containerPort: 8000 }]
          envFrom:
            - secretRef: { name: ngc-api-key }
          resources:
            limits:
              nvidia.com/gpu: 1
          volumeMounts:
            - { name: nim-cache, mountPath: /opt/nim/.cache }
          readinessProbe:
            httpGet: { path: /v1/health/ready, port: 8000 }
            initialDelaySeconds: 600     # weight load is slow
            periodSeconds: 30
      volumes:
        - name: nim-cache
          persistentVolumeClaim: { claimName: nim-cache-boltz2 }
---
apiVersion: v1
kind: Service
metadata:
  name: nim-boltz2
  namespace: bionemo
spec:
  selector: { app: nim-boltz2 }
  ports: [{ port: 8000, targetPort: 8000 }]
```

Repeat for `genmol`, `molmim`, `evo2`, `diffdock` (change image + PVC + Service
name). Evo2-40B needs a much larger GPU/VRAM footprint — give it its own node.

## Gateway → `BIONEMO_SELF_HOST_URL`

Front the per-model Services with one Ingress/gateway that maps the paths in
`bionemo_client._SELF_HOST_PATHS` to the right Service, e.g.:

| Path prefix | Service |
|---|---|
| `/biology/mit/boltz2/`   | `nim-boltz2:8000` |
| `/biology/nvidia/genmol/`| `nim-genmol:8000` |
| `/biology/nvidia/molmim/`| `nim-molmim:8000` |
| `/biology/arc/evo2-7b/`  | `nim-evo2:8000` |
| `/biology/mit/diffdock/` | `nim-diffdock:8000` |

Then set `BIONEMO_SELF_HOST_URL=http://<ingress-host>` on the BioMate backend.
If you skip the gateway and run one model per host, point
`BIONEMO_SELF_HOST_URL` at that host and override the route with
`BIONEMO_SELF_HOST_PATH_<MODEL>` as needed.

## Scaling / cost

- NIMs are stateless behind the weight cache → scale `replicas` horizontally per
  model based on queue depth; use a cluster autoscaler on the GPU node pool.
- Keep low-traffic models (Evo2-40B, AlphaFold2) scaled-to-zero / on-demand;
  BioMate's client degrades to an honest stub shape when a model is unreachable,
  so a scaled-down model does not fabricate results — it returns empty + a reason
  the API surfaces via `health()`.
