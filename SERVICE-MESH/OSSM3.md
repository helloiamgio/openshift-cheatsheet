# OpenShift Service Mesh 3 (OSSM 3) Cheatsheet operativo

> Focus: **OSSM 3 sidecar mode**, `Istio` + `IstioCNI`, **gateway injection**, **NodePort 30001/30002**, scheduling su **nodi infra**, comandi `oc`, troubleshooting e schema visivo finale.
>
> Linguaggio: pratico, da repo/runbook.

---

## 1) OSSM 3: cosa cambia davvero rispetto a OSSM 2

In OSSM 3 cambiano alcuni concetti base:

- **non esiste più `ServiceMeshControlPlane`** come CR principale: al suo posto c'è la risorsa **`Istio`**
- la CNI è gestita separatamente con la risorsa **`IstioCNI`**
- **Kiali, Prometheus, Tempo/Tracing** non sono più addon gestiti dal control plane: si installano e configurano **separatamente**
- i **gateway non sono più definiti dentro il control plane**: vanno gestiti come **Deployment/Service Kubernetes separati**, usando **gateway injection** oppure **Gateway API**
- la “membership” del mesh non si fa più con `SMMR`, ma con **`discoverySelectors` + label sui namespace**
- la sidecar injection segue la logica Istio standard: **`istio.io/rev=<revision>`** oppure `istio-injection=enabled` solo se lavori con la revisione/tag `default`

In pratica:

- **OSSM 2** = un CR grande (`SMCP`) che gestisce quasi tutto
- **OSSM 3** = control plane Istio più “puro”, gateway e osservabilità separati

---

## 2) Architettura minima OSSM 3

```text
+---------------------------------------------------------------+
|                       OpenShift Cluster                       |
|                                                               |
|  +----------------------+        +-------------------------+  |
|  |  OSSM 3 Operator     |        |  Kiali Operator        |  |
|  |  (Sail-based)        |        |  + Kiali Server/OSSMC  |  |
|  +----------+-----------+        +------------+------------+  |
|             |                                 |               |
|             v                                 v               |
|      +-------------+                   +-------------+        |
|      |   Istio     |------------------>|    Kiali    |        |
|      | (control    |                   | UI / graph  |        |
|      |  plane)     |                   +-------------+        |
|      +------+------+                                         |
|             | creates                                          |
|             v                                                  |
|      +-------------+                                           |
|      |IstioRevision|                                           |
|      +-------------+                                           |
|                                                               |
|      +-------------+                                           |
|      |  IstioCNI   |----> DaemonSet sui nodi                  |
|      +-------------+                                           |
|                                                               |
|   Namespace app / gateway visibili al mesh tramite           |
|   discoverySelectors + label namespace                        |
|                                                               |
|   +-------------------+        +---------------------------+  |
|   | Gateway namespace |        | Application namespace     |  |
|   | Deployment envoy  |        | pod + sidecar envoy       |  |
|   | (gateway inject)  |        | svc + workload            |  |
|   +---------+---------+        +-------------+-------------+  |
|             |                                    ^            |
|             +---- Gateway / VirtualService ------+            |
|                                                               |
|   Observability esterna al control plane:                     |
|   - OpenShift Monitoring / UWM                                |
|   - Tempo / Distributed Tracing Platform                      |
|   - Kiali                                                     |
+---------------------------------------------------------------+
```

---

## 3) Concetti chiave da ricordare

### 3.1 Control plane

Il control plane OSSM 3 è la risorsa:

- `apiVersion: sailoperator.io/v1`
- `kind: Istio`

È **cluster-wide** come risorsa, ma i pod del control plane vengono eseguiti nel namespace indicato in:

- `spec.namespace`

### 3.2 CNI

La CNI è separata:

- `apiVersion: sailoperator.io/v1`
- `kind: IstioCNI`

Installa un **DaemonSet cluster-wide** sui nodi.

### 3.3 Scope del mesh

In OSSM 3 il modo consigliato per limitare quali namespace siano gestiti dal mesh è:

- label sui namespace, ad esempio `istio-discovery=enabled`
- `spec.values.meshConfig.discoverySelectors`

### 3.4 Injection

Per fare injection lato workload:

- se usi una revisione non `default`, etichetta namespace/pod con  
  `istio.io/rev=<nome-istio-o-revision-tag>`
- `istio-injection=enabled` è utile solo quando lavori con `default`

### 3.5 Gateway

I gateway in OSSM 3 **non stanno nello `Istio` CR**.

Vanno creati come:

- `Deployment`
- `Service`
- opzionalmente `Route`
- risorse Istio `Gateway` e `VirtualService`

---

## 4) Flusso operativo consigliato

1. installa **Red Hat OpenShift Service Mesh 3 Operator**
2. crea namespace control plane (`istio-system`) e CNI (`istio-cni`) se non esistono
3. crea `Istio`
4. crea `IstioCNI`
5. verifica `IstioRevision`
6. applica `discoverySelectors`
7. etichetta i namespace applicativi e/o gateway
8. abilita injection con `istio.io/rev=<rev>`
9. crea gateway separato con gateway injection
10. crea `Gateway` + `VirtualService`
11. integra separatamente Kiali / Monitoring / Tempo

---

## 5) Installazione operator: nota pratica

Per l’installazione dell’Operator, in OSSM 3 conviene usare:

- canale **`stable`** per seguire l’ultima release supportata
- oppure **`stable-3.x`** per restare su una specifica linea di release

Per la versione del control plane puoi usare:

- una versione completa, ad esempio `v1.24.6`
- oppure l’alias `vX.Y-latest`, ad esempio `v1.24-latest`

---

## 6) Namespace base

```bash
oc create namespace istio-system
oc create namespace istio-cni
oc create namespace ingress-basic
oc create namespace app-demo
```

---

## 7) Manifest minimale `Istio` (cluster-wide, sidecar mode)

> Qui uso il nome **`basic`** perché è più vicino al tuo vecchio SMCP.  
> In questo caso, per injection userai **`istio.io/rev=basic`**.

```yaml
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: basic
spec:
  namespace: istio-system
  version: v1.24-latest
  updateStrategy:
    type: InPlace
  values:
    pilot:
      autoscaleEnabled: false
      replicaCount: 2
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
    meshConfig:
      enableAutoMtls: true
```

Apply:

```bash
oc apply -f istio-basic.yaml
```

Verifica:

```bash
oc get istio
oc get istiorevisions
oc get pods -n istio-system -l app=istiod
```

---

## 8) Manifest `IstioCNI`

```yaml
apiVersion: sailoperator.io/v1
kind: IstioCNI
metadata:
  name: default
spec:
  namespace: istio-cni
  version: v1.24-latest
```

Apply:

```bash
oc apply -f istiocni.yaml
```

Verifica:

```bash
oc get istiocni
oc get ds -n istio-cni
oc get pods -n istio-cni -o wide
```

---

## 9) Sostituto di SMMR: `discoverySelectors`

In OSSM 3, per limitare il mesh a namespace scelti:

### 9.1 Etichetta i namespace

```bash
oc label namespace istio-system istio-discovery=enabled --overwrite
oc label namespace ingress-basic istio-discovery=enabled --overwrite
oc label namespace app-demo istio-discovery=enabled --overwrite
```

### 9.2 Aggiorna la risorsa `Istio`

```yaml
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: basic
spec:
  namespace: istio-system
  version: v1.24-latest
  updateStrategy:
    type: InPlace
  values:
    pilot:
      autoscaleEnabled: false
      replicaCount: 2
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
    meshConfig:
      enableAutoMtls: true
      discoverySelectors:
        - matchLabels:
            istio-discovery: enabled
```

Apply:

```bash
oc apply -f istio-basic-scoped.yaml
```

---

## 10) Injection dei workload

Con `metadata.name: basic` sul control plane, abilita injection così:

```bash
oc label namespace app-demo istio.io/rev=basic --overwrite
```

Verifica la revisione:

```bash
oc get istiorevisions
```

Riavvia i deployment già esistenti:

```bash
oc rollout restart deploy -n app-demo
```

Verifica sidecar:

```bash
oc get pods -n app-demo
oc get pod -n app-demo <pod-name> -o jsonpath='{.spec.containers[*].name}{"\n"}'
```

---

## 11) Scheduling del control plane sui nodi infra

In OSSM 2 lo facevi con:

- `runtime.defaults.pod.nodeSelector`
- `runtime.components.pilot.pod.nodeSelector`

In OSSM 3 gli equivalenti sono:

- `spec.values.global.defaultNodeSelector`
- `spec.values.global.defaultTolerations`
- `spec.values.pilot.nodeSelector`
- `spec.values.pilot.tolerations`

### 11.1 Esempio `Istio` con control plane su nodi infra

```yaml
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: basic
spec:
  namespace: istio-system
  version: v1.24-latest
  updateStrategy:
    type: InPlace
  values:
    global:
      defaultNodeSelector:
        node-role.kubernetes.io/infra: ""
      defaultTolerations:
        - key: node-role.kubernetes.io/infra
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/infra
          operator: Exists
          effect: NoExecute
        - key: node.ocs.openshift.io/storage
          operator: Exists
          effect: NoSchedule
    pilot:
      autoscaleEnabled: false
      replicaCount: 2
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/infra
          operator: Exists
          effect: NoExecute
        - key: node.ocs.openshift.io/storage
          operator: Exists
          effect: NoSchedule
      resources:
        requests:
          cpu: 100m
          memory: 256Mi
    meshConfig:
      enableAutoMtls: true
      discoverySelectors:
        - matchLabels:
            istio-discovery: enabled
```

Apply:

```bash
oc apply -f istio-basic-infra.yaml
```

Verifica scheduling:

```bash
oc get pods -n istio-system -o wide
oc get nodes --show-labels | grep infra
```

> Nota: `IstioCNI` è un **DaemonSet cluster-wide**. Non lo “spostare” solo su infra: deve operare sui nodi che eseguono i workload del mesh.

---

## 12) Gateway injection: concetto operativo

In OSSM 3 il gateway è un **Envoy standalone** installato come:

- `Deployment`
- `Service`
- eventualmente `Route`

Per farlo funzionare:

- namespace gateway visibile al mesh via `discoverySelectors`
- `Deployment` con:
  - annotation `inject.istio.io/templates: gateway`
  - label `istio: <gateway-name>`
  - label `istio.io/rev: basic` (o la tua revisione attiva)
  - container `istio-proxy` con `image: auto`
- `Service` che seleziona `istio: <gateway-name>`

---

## 13) Gateway injection con NodePort 30001/30002 e nodi infra

### 13.1 Namespace gateway visibile al mesh

```bash
oc create namespace ingress-basic
oc label namespace ingress-basic istio-discovery=enabled --overwrite
```

---

### 13.2 RBAC per lettura secret TLS

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secret-reader
  namespace: ingress-basic
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: ingress-basic
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secret-reader
  namespace: ingress-basic
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: secret-reader
subjects:
  - kind: ServiceAccount
    name: secret-reader
    namespace: ingress-basic
```

Apply:

```bash
oc apply -f gateway-rbac.yaml
```

---

### 13.3 Deployment gateway su nodi infra

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: istio-ingressgateway
  namespace: ingress-basic
spec:
  replicas: 2
  selector:
    matchLabels:
      istio: ingress-basic
  template:
    metadata:
      annotations:
        inject.istio.io/templates: gateway
      labels:
        istio: ingress-basic
        istio.io/rev: basic
    spec:
      serviceAccountName: secret-reader
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
        - key: node-role.kubernetes.io/infra
          operator: Exists
          effect: NoSchedule
        - key: node-role.kubernetes.io/infra
          operator: Exists
          effect: NoExecute
        - key: node.ocs.openshift.io/storage
          operator: Exists
          effect: NoSchedule
      securityContext:
        sysctls:
          - name: net.ipv4.ip_unprivileged_port_start
            value: "0"
      containers:
        - name: istio-proxy
          image: auto
          securityContext:
            capabilities:
              drop:
                - ALL
            allowPrivilegeEscalation: false
            privileged: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
          ports:
            - name: http-envoy-prom
              containerPort: 15090
              protocol: TCP
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: "2"
              memory: 1Gi
```

Apply:

```bash
oc apply -f gateway-deployment.yaml
oc rollout status deployment/istio-ingressgateway -n ingress-basic
```

Verifica che l’injection sia avvenuta:

```bash
oc get pod -n ingress-basic
oc get pod -n ingress-basic <pod-name> -o jsonpath='{.spec.containers[*].name}{"\n"}'
```

---

### 13.4 Service NodePort 30001 / 30002

> A differenza di OSSM 2, qui il gateway è un normale `Service` Kubernetes.  
> Quindi i NodePort li metti direttamente nel `Service`.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: istio-ingressgateway
  namespace: ingress-basic
spec:
  type: NodePort
  selector:
    istio: ingress-basic
  ports:
    - name: status-port
      port: 15021
      protocol: TCP
      targetPort: 15021
    - name: http2
      port: 80
      protocol: TCP
      targetPort: 80
      nodePort: 30001
    - name: https
      port: 443
      protocol: TCP
      targetPort: 443
      nodePort: 30002
```

Apply:

```bash
oc apply -f gateway-service-nodeport.yaml
```

Verifica:

```bash
oc get svc -n ingress-basic istio-ingressgateway
oc get svc -n ingress-basic istio-ingressgateway -o jsonpath='{range .spec.ports[*]}{.name}{" port="}{.port}{" nodePort="}{.nodePort}{" targetPort="}{.targetPort}{"\n"}{end}'
```

---

## 14) Gateway e VirtualService

### 14.1 Gateway

```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: app-demo-gw
  namespace: app-demo
spec:
  selector:
    istio: ingress-basic
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - app-demo.example.com
```

### 14.2 VirtualService

```yaml
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: app-demo-vs
  namespace: app-demo
spec:
  hosts:
    - app-demo.example.com
  gateways:
    - app-demo-gw
  http:
    - route:
        - destination:
            host: myapp.app-demo.svc.cluster.local
            port:
              number: 8080
```

Apply:

```bash
oc apply -f gateway.yaml
oc apply -f virtualservice.yaml
```

Verifica:

```bash
oc get gateway -n app-demo
oc get virtualservice -n app-demo
```

---

## 15) Route OpenShift: esplicita, non automatica

In OSSM 3 non c’è più l’IOR che crea route automaticamente dal gateway.

Se vuoi una route OpenShift esplicita:

```bash
oc expose service istio-ingressgateway -n ingress-basic
oc get route -n ingress-basic
```

> Se invece usi F5/VIP esterno e NodePort, la route può non servirti.

---

## 16) Mini esempio app namespace

Namespace:

```bash
oc label namespace app-demo istio-discovery=enabled --overwrite
oc label namespace app-demo istio.io/rev=basic --overwrite
```

Deployment restart:

```bash
oc rollout restart deployment -n app-demo
```

Verifica pod con sidecar:

```bash
oc get pods -n app-demo
oc get pod -n app-demo <pod> -o jsonpath='{.spec.containers[*].name}{"\n"}'
```

---

## 17) Comandi utili da usare sempre

### 17.1 Stato operator / CR principali

```bash
oc get istio
oc get istiorevisions
oc get istiorevisiontags
oc get istiocni
```

### 17.2 Pod control plane / CNI

```bash
oc get pods -n istio-system -l app=istiod -o wide
oc get ds -n istio-cni
oc get pods -n istio-cni -o wide
```

### 17.3 Namespace e label

```bash
oc get ns --show-labels | egrep 'istio-discovery|istio.io/rev|istio-injection'
```

### 17.4 Gateway

```bash
oc get deploy,svc -n ingress-basic
oc get gateway,virtualservice -A
```

### 17.5 Verifiche scheduling su infra

```bash
oc get pods -n istio-system -o wide
oc get pods -n ingress-basic -o wide
oc get nodes --show-labels | grep node-role.kubernetes.io/infra
oc describe node <infra-node> | egrep -i 'taints|Roles'
```

### 17.6 Scoprire tutti i campi configurabili

```bash
oc explain istios
oc explain istios.spec
oc explain istios.spec.values
oc explain istiocnis
oc explain istiocnis.spec
```

---

## 18) Patch rapide

### 18.1 Aggiungere `discoverySelectors`

```bash
oc patch istio basic --type merge -p '
spec:
  values:
    meshConfig:
      discoverySelectors:
      - matchLabels:
          istio-discovery: enabled
'
```

### 18.2 Spostare il control plane sui nodi infra

```bash
oc patch istio basic --type merge -p '
spec:
  values:
    global:
      defaultNodeSelector:
        node-role.kubernetes.io/infra: ""
      defaultTolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
      - key: node.ocs.openshift.io/storage
        operator: Exists
        effect: NoSchedule
    pilot:
      nodeSelector:
        node-role.kubernetes.io/infra: ""
      tolerations:
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoSchedule
      - key: node-role.kubernetes.io/infra
        operator: Exists
        effect: NoExecute
      - key: node.ocs.openshift.io/storage
        operator: Exists
        effect: NoSchedule
'
```

### 18.3 Etichettare namespace app per mesh + injection

```bash
oc label namespace app-demo istio-discovery=enabled --overwrite
oc label namespace app-demo istio.io/rev=basic --overwrite
```

---

## 19) Troubleshooting rapido

### 19.1 Nessun sidecar nei pod applicativi

Controlla:

- il namespace è etichettato con `istio.io/rev=basic`?
- il namespace è incluso dai `discoverySelectors`?
- il deployment è stato restartato?
- il control plane è `Healthy`?
- esiste l’`IstioRevision` corretta?

Comandi:

```bash
oc get istio
oc get istiorevisions
oc get ns app-demo --show-labels
oc rollout restart deploy -n app-demo
```

---

### 19.2 Il gateway non viene “injectato”

Controlla il `Deployment` gateway:

- annotation `inject.istio.io/templates: gateway`
- label `istio: ingress-basic`
- label `istio.io/rev: basic`
- container `istio-proxy` con `image: auto`

Comandi:

```bash
oc get deploy -n ingress-basic istio-ingressgateway -o yaml
oc get pods -n ingress-basic
oc get pod -n ingress-basic <pod> -o jsonpath='{.spec.containers[*].name}{"\n"}'
```

---

### 19.3 Il control plane non va sui nodi infra

Controlla:

- label nodi infra
- taint reali dei nodi
- `spec.values.global.defaultNodeSelector`
- `spec.values.global.defaultTolerations`
- `spec.values.pilot.nodeSelector`
- `spec.values.pilot.tolerations`

Comandi:

```bash
oc get nodes --show-labels | grep infra
oc describe node <infra-node> | egrep -i 'Taints|Roles'
oc get istio basic -o yaml
oc get pods -n istio-system -o wide
```

---

### 19.4 Il gateway è su worker invece che su infra

Ricorda: in OSSM 3 il gateway è **fuori dal control plane**.  
Quindi il suo scheduling si fa nel **Deployment del gateway**, non nella risorsa `Istio`.

Controlla:

```bash
oc get deploy -n ingress-basic istio-ingressgateway -o yaml
oc get pods -n ingress-basic -o wide
```

---

### 19.5 `ServiceMeshControlPlane` / `SMMR` non esistono

Corretto: in OSSM 3 devi ragionare così:

- `SMCP` -> `Istio`
- `SMMR` -> `discoverySelectors` + label namespace
- gateway definiti nello SMCP -> gateway injection / Gateway API
- addon osservabilità -> operator separati

---

### 19.6 NodePort non raggiungibile

Controlla:

```bash
oc get svc -n ingress-basic istio-ingressgateway
oc get endpoints -n ingress-basic istio-ingressgateway
oc get pods -n ingress-basic -o wide
```

Poi verifica:

- firewall
- F5 / VIP
- security rules
- reachability verso nodi infra
- porta 30001/30002 aperta

---

## 20) Mapping mentale OSSM 2 -> OSSM 3

| OSSM 2 | OSSM 3 |
|---|---|
| `ServiceMeshControlPlane` | `Istio` |
| `ServiceMeshMemberRoll` | `discoverySelectors` + label namespace |
| gateway in `spec.gateways.*` dello SMCP | `Deployment` + `Service` + `Gateway` + `VirtualService` |
| addon in SMCP (`grafana`, `kiali`, `jaeger`, `prometheus`) | installazione/configurazione separata |
| IOR / route automatiche | route esplicite |
| nodeSelector/tolerations in `runtime.*` | `spec.values.global.*`, `spec.values.pilot.*`, oppure nel Deployment del gateway |

---

## 21) Esempio completo “reference set” per sidecar mode

Ordine file consigliato:

```text
00-namespaces.yaml
01-istio-basic.yaml
02-istiocni.yaml
03-label-namespaces.sh
04-gateway-rbac.yaml
05-gateway-deployment.yaml
06-gateway-service-nodeport.yaml
07-gateway.yaml
08-virtualservice.yaml
```

Ordine apply:

```bash
oc apply -f 00-namespaces.yaml
oc apply -f 01-istio-basic.yaml
oc apply -f 02-istiocni.yaml
bash 03-label-namespaces.sh
oc apply -f 04-gateway-rbac.yaml
oc apply -f 05-gateway-deployment.yaml
oc apply -f 06-gateway-service-nodeport.yaml
oc apply -f 07-gateway.yaml
oc apply -f 08-virtualservice.yaml
```

---

## 22) Schema visivo: come gira una request in OSSM 3

### 22.1 Caso NodePort/F5 verso ingress gateway

```text
Utente / Client
      |
      v
+-------------+
| F5 / VIP /  |
| LB esterno  |
+-------------+
      |
      | TCP 30001 / 30002
      v
+----------------------------------------------+
| Service NodePort istio-ingressgateway         |
| namespace: ingress-basic                      |
| ports: 80->30001, 443->30002                 |
+-------------------+--------------------------+
                    |
                    v
+----------------------------------------------+
| Deployment istio-ingressgateway              |
| gateway injection                            |
| pod schedulati sui nodi infra                |
| labels: istio=ingress-basic                  |
| rev: basic                                   |
+-------------------+--------------------------+
                    |
                    | selezione da risorsa Gateway
                    v
+----------------------------------------------+
| Istio Gateway                                |
| namespace applicativo                        |
| selector: istio=ingress-basic                |
+-------------------+--------------------------+
                    |
                    | routing L7
                    v
+----------------------------------------------+
| VirtualService                               |
| host/path matching                           |
| route verso service Kubernetes               |
+-------------------+--------------------------+
                    |
                    v
+----------------------------------------------+
| Service app-demo / workload target           |
+-------------------+--------------------------+
                    |
                    v
+----------------------------------------------+
| Pod applicativo + sidecar Envoy              |
| namespace etichettato con                    |
| - istio-discovery=enabled                    |
| - istio.io/rev=basic                         |
+----------------------------------------------+
```

### 22.2 Cosa fa ogni componente

- **OSSM 3 Operator**  
  gestisce lifecycle di `Istio`, `IstioRevision`, `IstioCNI`, `ZTunnel`

- **Istio**  
  è il CR principale del control plane

- **IstioRevision**  
  rappresenta una revisione concreta del control plane; utile per canary update e revision-based upgrades

- **IstioCNI**  
  installa il plugin CNI sui nodi; evita privilegi elevati nei pod applicativi

- **discoverySelectors**  
  dicono quali namespace il control plane deve considerare parte del mesh

- **`istio.io/rev=<rev>`**  
  collega workload/gateway a una specifica revisione/control plane

- **Gateway injection**  
  trasforma un normale deployment/service Kubernetes in un gateway Envoy gestito dal mesh

- **Gateway / VirtualService**  
  descrivono il routing L7

- **Kiali**  
  vista topologica, validazioni, collegamenti a metriche e tracing

- **Tempo / Distributed Tracing Platform**  
  tracing distribuito integrato separatamente

- **OpenShift Monitoring / UWM**  
  metriche di mesh e workload

---

## 23) Checklist finale “pronta all’uso”

### Control plane
- [ ] Operator OSSM 3 installato
- [ ] `Istio` creato
- [ ] `IstioCNI` creato
- [ ] `IstioRevision` Healthy
- [ ] `istiod` running

### Scope mesh
- [ ] namespace control plane etichettato con `istio-discovery=enabled`
- [ ] namespace app etichettati con `istio-discovery=enabled`
- [ ] namespace app etichettati con `istio.io/rev=<rev>`

### Infra scheduling
- [ ] control plane schedulato su infra con `values.global/pilot`
- [ ] gateway schedulato su infra nel suo `Deployment`

### Gateway
- [ ] RBAC secret-reader creato
- [ ] Deployment gateway injectato
- [ ] Service NodePort 30001/30002 creato
- [ ] `Gateway` creato
- [ ] `VirtualService` creato

### Observability
- [ ] UWM/Monitoring disponibile
- [ ] Kiali installato separatamente
- [ ] Tempo integrato separatamente

---

## 24) Fonti ufficiali Red Hat usate per costruire questo cheatsheet

- OpenShift Service Mesh 3.0 - Installing  
- OpenShift Service Mesh 3.0 - Gateways  
- OpenShift Service Mesh 3.0 - About  
- OpenShift Service Mesh 3.0 - Observability  
- OpenShift Service Mesh 3.0 - Migrating from Service Mesh 2 to Service Mesh 3  
- OpenShift Service Mesh 3.x - Updating / Release Notes

Riferimenti operativi principali:
- `Istio` al posto di `ServiceMeshControlPlane`
- `IstioCNI` separato
- `discoverySelectors` al posto di `SMMR`
- gateway gestiti separatamente
- route OpenShift esplicite
- scheduling infra del control plane via `spec.values.global.*` e `spec.values.pilot.*`
- scheduling infra dei gateway via normale `Deployment.spec.template.spec`

---
