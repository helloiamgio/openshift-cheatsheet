# Migrazione da OpenShift Service Mesh 2 a OpenShift Service Mesh 3

## Premessa

La migrazione da OpenShift Service Mesh 2 a 3 **non è un upgrade in-place del control plane**, ma una **migrazione affiancata**:

- OSSM 2 usa **Maistra** e il CR `ServiceMeshControlPlane`
- OSSM 3 usa il nuovo Operator basato su **Sail / Istio** e il CR `Istio`
- in OSSM 3 i **gateway non sono più gestiti dal control plane**
- observability e tracing vanno gestiti con **componenti separati**

La guida ufficiale vale per chi è già su **OSSM 2.6.14** e vuole passare a **OSSM 3.0**. Se sei sotto 2.6.14, devi prima aggiornare.

> Nota pratica: negli esempi della guida compaiono versioni come `v1.24.3` o `v1.24.6`, ma in produzione conviene usare **l’ultima patch supportata** della linea 3.0 che installerai sul cluster.

---

## 1. Congelare il più possibile i cambiamenti sulla mesh attuale

Durante la migrazione Red Hat raccomanda di:

- mettere gli aggiornamenti automatici in **Manual**
- ridurre al minimo le modifiche a traffico, security, gateway e workload
- evitare di trascinare la migrazione troppo a lungo

Se devi aggiungere un nuovo namespace applicativo mentre la migrazione è in corso, quel namespace deve essere gestito dal control plane OSSM 3 e va etichettato con:

```bash
maistra.io/ignore-namespace="true"
```

in modo da evitare conflitti con OSSM 2.

---

## 2. Verificare il go / no-go tecnico

Prima di partire vanno verificati almeno questi punti:

- sei su **OSSM 2.6.14**
- hai aggiornato lo `ServiceMeshControlPlane` alla sua ultima patch supportata
- hai installato il **Service Mesh 3 Operator**
- installerai anche `IstioCNI`
- sai se il deployment è **MultiTenant** o **ClusterWide**
- sai se usi **cert-manager / istio-csr**

### Comandi utili

```bash
oc get smcp <smcp-name> -n <smcp-namespace> -o jsonpath='{.spec.mode}'; echo
oc get smcp <smcp-name> -n <smcp-namespace> -o jsonpath='{.spec.security.certificateAuthority.type}'; echo
```

Interpretazione:

- se `.spec.mode` è vuoto, il deployment va considerato **MultiTenant**
- se il secondo comando restituisce `cert-manager`, devi seguire il ramo con **cert-manager**

---

## 3. Pulire i punti che possono bloccare l’installazione di OSSM 3

OSSM 3 può **fallire l’installazione** se nel cluster ci sono `ServiceEntry` vecchi incompatibili con Istio 1.24, in particolare:

- `ServiceEntry` con **più di 256 host**
- `ServiceEntry` senza **porte definite**

### Controlli consigliati

```bash
oc get serviceentries -A -o json | jq -r '.items[] | select(.spec.hosts | length > 256) | "\(.metadata.namespace)/\(.metadata.name): \(.spec.hosts | length) hosts"'
oc get serviceentries -A -o json | jq -r '.items[] | select(.spec.ports == null or (.spec.ports | length == 0)) | "\(.metadata.namespace)/\(.metadata.name)"'
```

Se trovi casi del genere:

- splitta i `ServiceEntry` con troppi host
- completa la sezione `ports` dove manca

Questo va fatto **prima di installare l’Operator 3**.

---

## 4. Eseguire tutta la checklist di premigrazione su OSSM 2

Questa parte va fatta **prima** di migrare workload e gateway.

Sul vecchio `ServiceMeshControlPlane` devi:

- disabilitare **Prometheus**
- disabilitare **tracing** integrato
- disabilitare **Kiali** gestito dal mesh operator
- disabilitare **Grafana**
- portare metriche / tracing verso integrazioni esterne supportate, tipicamente:
  - **User Workload Monitoring**
  - **Tempo / OpenTelemetry**
  - **Kiali standalone**

### Parametri da modificare nel vecchio SMCP

```yaml
spec:
  security:
    manageNetworkPolicy: false
  addons:
    grafana:
      enabled: false
    kiali:
      enabled: false
    prometheus:
      enabled: false
  tracing:
    type: None
```

Inoltre bisogna verificare due migrazioni architetturali:

1. se usi **IOR** (Istio OpenShift Routing), devi passare a **route esplicitamente gestite**
2. se i gateway sono ancora definiti / gestiti dentro SMCP, devi passare a **gateway injection**, perché OSSM 3 non crea né gestisce i gateway

---

## 5. Decidere cosa fare con le NetworkPolicy

OSSM 2, quando `spec.security.manageNetworkPolicy=true`, crea NetworkPolicy. OSSM 3 **non lo fa**.

Hai due strade:

### Strada semplice

- metti `spec.security.manageNetworkPolicy=false`
- migri workload e control plane
- ricrei le policy **dopo** la migrazione

### Strada più rigida

Se non puoi stare senza policy durante la migrazione:

- ricreale **prima**
- poi metti comunque `spec.security.manageNetworkPolicy=false`
- prosegui con la migrazione

### Regola fondamentale

Durante la coesistenza dei due control plane:

- entrambi devono poter parlare con **tutti i workload**
- i workload devono poter parlare con entrambi i control plane
- non puoi più basarti sul label `maistra.io/member-of` per costruire le nuove policy

---

# Scelta del percorso di migrazione

## Caso A — Mesh MultiTenant

Questo è il caso in cui in OSSM 2 i namespace erano arruolati tramite `ServiceMeshMemberRoll`, mentre in OSSM 3 devi passare a:

- `discoverySelectors`
- label sui namespace

### Sequenza corretta

#### 1. Creare il nuovo CR `Istio`

Va creato **nello stesso namespace** del vecchio `ServiceMeshControlPlane`.

> Se `spec.namespace` del nuovo `Istio` non coincide con il namespace del vecchio SMCP, la migrazione non si completa correttamente.

Esempio minimale:

```yaml
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: istio-tenant-a
spec:
  namespace: istio-system-tenant-a
  version: v1.24.3
  values:
    meshConfig:
      discoverySelectors:
      - matchLabels:
          tenant: tenant-a
      extensionProviders:
      - name: prometheus
        prometheus: {}
      - name: otel
        opentelemetry:
          port: 4317
          service: otel-collector.opentelemetrycollector-3.svc.cluster.local
```

#### 2. Etichettare i namespace dataplane

```bash
oc label ns <namespace> tenant=tenant-a
```

Questo sostituisce l’arruolamento che prima veniva fatto tramite `ServiceMeshMemberRoll`.

#### 3. Recuperare la revisione attiva del nuovo mesh

```bash
oc get istios istio-tenant-a
```

#### 4. Spostare il namespace sul nuovo control plane

```bash
oc label ns <namespace> istio.io/rev=<active-revision> maistra.io/ignore-namespace="true" --overwrite=true
```

Effetto:

- il namespace viene iniettato dal nuovo control plane OSSM 3
- OSSM 2 smette di occuparsene

> Senza `maistra.io/ignore-namespace="true"`, il webhook di OSSM 2 continua a tentare l’injection e i pod possono non partire perché si ritrovano annotazioni CNI sia 2.x sia 3.x.

#### 5. Riavviare i workload

Tutti insieme:

```bash
oc rollout restart deployments -n <namespace>
```

Oppure singolarmente:

```bash
oc rollout restart deployment <deployment> -n <namespace>
```

Poi attendere il rollout:

```bash
oc rollout status deployment <deployment> -n <namespace>
```

#### 6. Verifica

```bash
istioctl ps --istioNamespace <istio-namespace> --revision <active-revision>
```

E test applicativo reale, per esempio via `curl` dentro il proxy di un pod.

---

## Caso B — Mesh MultiTenant con cert-manager / istio-csr

La sequenza è simile al multitenant, ma **prima di creare il nuovo `Istio`** bisogna aggiornare `istio-csr`.

### 1. Verificare che SMCP usi cert-manager

```bash
oc get smcp <smcp-name> -n <smcp-namespace> -o jsonpath='{.spec.security.certificateAuthority.type}'; echo
```

Se restituisce `cert-manager`, segui questo ramo.

### 2. Aggiornare `istio-csr`

```bash
helm upgrade cert-manager-istio-csr jetstack/cert-manager-istio-csr \
  --install \
  --reuse-values \
  --namespace istio-system \
  --wait \
  --set "app.istio.revisions={basic,istio-tenant-a}"
```

Il nuovo control plane OSSM 3 deve comparire in `app.istio.revisions` **prima** di creare l’`Istio`.

### 3. Creare il nuovo `Istio`

Esempio con cert-manager:

```yaml
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: istio-tenant-a
spec:
  namespace: istio-system-tenant-a
  version: v1.24.3
  values:
    meshConfig:
      discoverySelectors:
      - matchLabels:
          tenant: tenant-a
      extensionProviders:
      - name: prometheus
        prometheus: {}
      - name: otel
        opentelemetry:
          port: 4317
          service: otel-collector.opentelemetrycollector-3.svc.cluster.local
    global:
      caAddress: cert-manager-istio-csr.istio-system.svc:443
    pilot:
      env:
        ENABLE_CA_SERVER: "false"
```

### 4. Migrazione workload

Uguale al caso multitenant:

```bash
oc label ns <namespace> tenant=tenant-a
oc get istios istio-tenant-a
oc label ns <namespace> istio.io/rev=<active-revision> maistra.io/ignore-namespace="true" --overwrite=true
oc rollout restart deployments -n <namespace>
```

### 5. Dopo la migrazione completa

Aggiornare `app.controller.configmapNamespaceSelector` di `istio-csr` in modo che punti ai namespace del nuovo mesh.

---

## Caso C — Mesh ClusterWide

In OSSM 3 tutti i mesh sono di fatto cluster-scoped. I vecchi `ServiceMeshMemberRoll` e `ServiceMeshMember` non esistono più. La scoperta dei namespace va controllata con `discoverySelectors`.

### Metodi disponibili

Per il cluster-wide Red Hat propone tre metodi:

1. **`istio.io/rev`** → metodo più controllato / canary
2. **`istio-injection=enabled`** → valido in certi scenari cluster-wide
3. **simple migration** → **da non usare in produzione**

### Raccomandazione pratica

Per produzione: usa il metodo **`istio.io/rev`**.

### Sequenza con `istio.io/rev`

#### 1. Identificare il namespace del vecchio SMCP

```bash
oc get smcp -A
```

#### 2. Creare il nuovo CR `Istio`

Va creato nello **stesso namespace** del vecchio SMCP. Di norma conviene usare:

```yaml
spec:
  updateStrategy:
    type: RevisionBased
```

Se vuoi limitare l’ambito del nuovo control plane, aggiungi `discoverySelectors`.

#### 3. Recuperare la revisione attiva

```bash
oc get istios
```

#### 4. Migrare i namespace dataplane

```bash
oc label ns <namespace> istio.io/rev=<active-revision> maistra.io/ignore-namespace="true" istio-injection- --overwrite=true
```

Questa operazione:

- rimuove `istio-injection`
- aggiunge `istio.io/rev=<active-revision>`
- aggiunge `maistra.io/ignore-namespace="true"`

> Nel cluster-wide questo è fondamentale: se usi `istio.io/rev`, devi rimuovere `istio-injection`, perché `istio-injection` ha precedenza e impedisce al nuovo control plane di fare injection.

#### 5. Riavviare i workload

```bash
oc rollout restart deployments -n <namespace>
oc rollout status deployment <deployment> -n <namespace>
```

#### 6. Verifica

```bash
istioctl ps -n <namespace>
```

---

## Caso D — Mesh ClusterWide con cert-manager / istio-csr

Questo caso segue la stessa logica del cluster-wide, ma con un passaggio in più prima di creare il nuovo `Istio`.

### Sequenza sintetica

1. verificare che il vecchio SMCP usi `cert-manager`
2. aggiornare `istio-csr` aggiungendo la nuova revisione OSSM 3 a `app.istio.revisions`
3. creare il nuovo `Istio`
4. spostare i namespace sul nuovo control plane
5. riavviare workload
6. verificare che il nuovo `istiod` usi il certificato root esistente

Esempio di verifica:

```bash
oc logs deployments/istiod-<nuova-revisione> -n <istio-namespace> | grep 'Load signing key and cert from existing secret'
```

---

# Gateways

I gateway **non vengono più creati né gestiti** dal control plane OSSM 3. Vanno quindi migrati separatamente.

## Approcci possibili

1. **Gateway canary migration**
   - rollout graduale
   - massimo controllo
   - consigliato in produzione

2. **Gateway in place migration**
   - meno controllo
   - più semplice

### Approccio consigliato

Per ambienti produttivi conviene preferire il **canary** anche sui gateway.

In ogni caso:

- il namespace gateway va etichettato verso il nuovo mesh
- va aggiunto `maistra.io/ignore-namespace="true"`
- si riavvia il deployment gateway
- si verifica con `istioctl ps`
- si testano le route applicative

Esempio:

```bash
oc label namespace <gateway_namespace> istio.io/rev=<istio_revision_name> maistra.io/ignore-namespace="true"
oc -n <gateway_namespace> rollout restart deployment <gateway_name>
istioctl ps -n <gateway_namespace>
```

---

# Cose che cambiano davvero e vanno verificate una per una

Se in OSSM 2 usavi certe feature, non basta portare il vecchio YAML.

## Grafana

Grafana **non è supportato** in OSSM 3.

## Kiali

Kiali resta supportato, ma come componente / operator separato.

## NetworkPolicy

OSSM 3 non le crea automaticamente.

## mTLS strict e TLS

I settaggi del vecchio SMCP non si traslano 1:1:

- per strict mTLS in OSSM 3 devi usare `PeerAuthentication` e `DestinationRule`
- il minimo TLS va configurato nel nuovo `Istio` sotto:

```yaml
spec:
  meshConfig:
    tlsDefaults:
      minProtocolVersion: ...
```

## Federation

Se usavi **federation** in OSSM 2, va verificato con molta attenzione il redesign architetturale, perché OSSM 3 introduce i modelli multi-cluster Istio (`multi-primary`, `primary-remote`, `external control plane`) e il vecchio modello non va dato per scontato come equivalente diretto.

---

# Chiusura della migrazione

Quando hai migrato **tutti** i workload e **tutti** i gateway, puoi completare la pulizia.

## 1. Ricreare le NetworkPolicy, se rimandate

- ricrearle sul nuovo mesh
- aggiornare selector e label

## 2. Rimuovere le risorse OSSM 2

```bash
oc get smcp,smm,smmr -A
oc delete smcp --all -A
oc delete smmr --all -A
oc delete smm --all -A
oc get smcp,smm,smmr -A
```

## 3. Rimuovere l’Operator 2 e le CRD Maistra

```bash
csv=$(oc get subscription servicemeshoperator -n openshift-operators -o yaml | grep currentCSV | cut -f 2 -d ':')
oc delete subscription servicemeshoperator -n openshift-operators
oc delete clusterserviceversion $csv -n openshift-operators
oc get crds -o name | grep ".*\.maistra\.io" | xargs -r -n 1 oc delete
```

## 4. Togliere i label temporanei Maistra

```bash
oc get namespace -l maistra.io/ignore-namespace="true"
oc label namespace <namespace> maistra.io/ignore-namespace-
```

---

# Piano operativo consigliato

Per un cluster reale, il piano corretto è questo:

1. inventario completo del mesh 2
2. classificazione: **multitenant o cluster-wide**, **con o senza cert-manager**
3. premigration checklist completa
4. installazione OSSM 3 Operator + `IstioCNI`
5. creazione nuovo `Istio` CR
6. migrazione **namespace per namespace** con `istio.io/rev` e `maistra.io/ignore-namespace`
7. migrazione gateway
8. test funzionali + `istioctl ps` + telemetria
9. pulizia finale OSSM 2

---

# Dati reali da raccogliere per adattare la procedura al cluster

Per costruire un runbook preciso cluster-specifico, raccogli questi output:

```bash
oc version
oc get clusterversion
oc get smcp -A -o yaml
oc get smmr -A -o yaml
oc get smm -A -o yaml
oc get subscription -A | egrep 'servicemesh|kiali|jaeger|tempo|opentelemetry'
oc get ns --show-labels
oc get gateway,virtualservice,destinationrule,peerauthentication,authorizationpolicy,serviceentry -A -o yaml
oc get deployment -A | egrep 'istio|kiali|jaeger|tempo|otel|cert-manager|istio-csr'
```

Con questi dati si può definire in modo puntuale:

- il ramo corretto di migrazione
- i possibili blocker
- l’ordine esatto dei rollout
- i manifest `Istio` iniziali
- la strategia di migrazione dei gateway

---

# Fonti ufficiali

- Red Hat OpenShift Service Mesh 3.0 — Migrating from Service Mesh 2 to Service Mesh 3  
  https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html-single/migrating_from_service_mesh_2_to_service_mesh_3/index

- Before migrating  
  https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/migrating_from_service_mesh_2_to_service_mesh_3/before-migrating

- Multitenant migration guide  
  https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/migrating_from_service_mesh_2_to_service_mesh_3/multitenant-migration-guide

- Migrating gateways  
  https://docs.redhat.com/en/documentation/red_hat_openshift_service_mesh/3.0/html/migrating_from_service_mesh_2_to_service_mesh_3/migrating-gateways

- Release notes 3.0  
  https://docs.redhat.com/it/documentation/red_hat_openshift_service_mesh/3.0/html-single/release_notes/index
