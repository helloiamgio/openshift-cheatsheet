# OpenShift 4.18 - Comandi utili per consultare i log di audit

Questa cheat sheet è basata sulla documentazione Red Hat **OpenShift Container Platform 4.18** per la visualizzazione dei log di audit.

## Prerequisiti

- accesso al cluster con ruolo `cluster-admin`
- client `oc` installato
- `jq` installato per filtrare i log JSON

---

## 1) Elencare i control plane node

```bash
oc get nodes -l node-role.kubernetes.io/master=
```

Oppure:

```bash
oc get nodes -l node-role.kubernetes.io/control-plane=
```

---

## 2) Elencare i file di audit disponibili sui master

### OpenShift API Server

```bash
oc adm node-logs --role=master --path=openshift-apiserver/
```

### Kubernetes API Server

```bash
oc adm node-logs --role=master --path=kube-apiserver/
```

### OpenShift OAuth API Server

```bash
oc adm node-logs --role=master --path=oauth-apiserver/
```

### OpenShift OAuth Server

```bash
oc adm node-logs --role=master --path=oauth-server/
```

---

## 3) Leggere un file di audit specifico da un master

### OpenShift API Server

```bash
oc adm node-logs <node_name> --path=openshift-apiserver/<log_name>
```

Esempio:

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log
```

### Kubernetes API Server

```bash
oc adm node-logs <node_name> --path=kube-apiserver/<log_name>
```

### OpenShift OAuth API Server

```bash
oc adm node-logs <node_name> --path=oauth-apiserver/<log_name>
```

### OpenShift OAuth Server

```bash
oc adm node-logs <node_name> --path=oauth-server/<log_name>
```

---

## 4) Comandi rapidi di consultazione

### Leggere le prime righe

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log | head
```

### Leggere le ultime righe

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log | tail
```

### Formattare JSON con jq

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log | jq .
```

### Salvare localmente il log

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log > openshift-apiserver-audit.log
```

---

## 5) Filtrare i log di audit con jq

### Filtrare per username

```bash
oc adm node-logs master-0.example.com \
  --path=openshift-apiserver/audit.log \
  | jq 'select(.user.username == "myusername")'
```

### Filtrare per userAgent

```bash
oc adm node-logs master-0.example.com \
  --path=openshift-apiserver/audit.log \
  | jq 'select(.userAgent == "cluster-version-operator/v0.0.0 (linux/amd64) kubernetes/$Format")'
```

### Filtrare Kubernetes API audit logs per API path/versione e stampare solo la userAgent

```bash
oc adm node-logs master-0.example.com \
  --path=kube-apiserver/audit.log \
  | jq 'select(.requestURI | startswith("/apis/apiextensions.k8s.io/v1beta1")) | .userAgent'
```

### Escludere un verbo, ad esempio GET, nei log OAuth API server

```bash
oc adm node-logs master-0.example.com \
  --path=oauth-apiserver/audit.log \
  | jq 'select(.verb != "get")'
```

### Trovare eventi OAuth server con username identificato e decisione in errore

```bash
oc adm node-logs master-0.example.com \
  --path=oauth-server/audit.log \
  | jq 'select(.annotations["authentication.openshift.io/username"] != null and .annotations["authentication.openshift.io/decision"] == "error")'
```

---

## 6) Filtri pratici aggiuntivi utili

### Vedere solo le create

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq 'select(.verb == "create")'
```

### Vedere solo delete o deletecollection

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq 'select(.verb == "delete" or .verb == "deletecollection")'
```

### Vedere solo operazioni fallite

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq 'select(.responseStatus.code >= 400)'
```

### Filtrare per namespace target

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq 'select(.objectRef.namespace == "mio-namespace")'
```

### Filtrare per resource type

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq 'select(.objectRef.resource == "secrets")'
```

### Filtrare per nome oggetto

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq 'select(.objectRef.name == "my-secret")'
```

### Filtrare per IP sorgente

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq 'select(.sourceIPs[]? == "10.10.10.10")'
```

### Estrarre solo alcuni campi utili in formato compatto

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq -c '{ts: .requestReceivedTimestamp, user: .user.username, verb: .verb, uri: .requestURI, ns: .objectRef.namespace, resource: .objectRef.resource, name: .objectRef.name, code: .responseStatus.code}'
```

---

## 7) Grep veloce senza jq

### Cercare uno username

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log | grep -i myusername
```

### Cercare un namespace

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log | grep -i mio-namespace
```

### Cercare requests su secrets

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log | grep '"resource":"secrets"'
```

---

## 8) Consultare audit log ruotati

Se nell'elenco compaiono file ruotati come `audit-<timestamp>.log`, puoi leggerli così:

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit-2026-03-26T00-00-00.000.log
```

---

## 9) Raccogliere tutti i log di audit con must-gather

```bash
oc adm must-gather -- /usr/bin/gather_audit_logs
```

Comprimere poi la directory generata:

```bash
tar cvaf must-gather-audit.tar.gz must-gather.local.*
```

---

## 10) One-liner utili per troubleshooting

### Chi ha cancellato qualcosa in un namespace

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq 'select(.objectRef.namespace == "mio-namespace" and (.verb == "delete" or .verb == "deletecollection")) | {ts: .requestReceivedTimestamp, user: .user.username, verb: .verb, resource: .objectRef.resource, name: .objectRef.name, code: .responseStatus.code}'
```

### Chi ha letto dei secret

```bash
oc adm node-logs master-0.example.com --path=openshift-apiserver/audit.log \
  | jq 'select(.objectRef.resource == "secrets") | {ts: .requestReceivedTimestamp, user: .user.username, verb: .verb, ns: .objectRef.namespace, name: .objectRef.name, code: .responseStatus.code}'
```

### Errori di autenticazione OAuth

```bash
oc adm node-logs master-0.example.com --path=oauth-server/audit.log \
  | jq 'select(.annotations["authentication.openshift.io/decision"] == "error") | {ts: .requestReceivedTimestamp, username: .annotations["authentication.openshift.io/username"], reason: .annotations["authentication.openshift.io/reason"]}'
```

### Chiamate API fatte da un service account

```bash
oc adm node-logs master-0.example.com --path=kube-apiserver/audit.log \
  | jq 'select(.user.username | startswith("system:serviceaccount:")) | {ts: .requestReceivedTimestamp, sa: .user.username, verb: .verb, uri: .requestURI, code: .responseStatus.code}'
```

---

## 11) Note operative

- I log di audit API sono consultabili sui **control plane nodes** tramite `oc adm node-logs`.
- I percorsi principali sono:
  - `openshift-apiserver/`
  - `kube-apiserver/`
  - `oauth-apiserver/`
  - `oauth-server/`
- Il contenuto effettivamente registrato dipende dalla **audit policy** configurata sul cluster.
- In ambienti con OpenShift Logging/Loki, i log di audit possono anche essere inoltrati e consultati centralmente, ma i comandi sopra restano quelli documentati per l'accesso diretto secondo Red Hat.

---

## Fonti

- Red Hat OpenShift Container Platform 4.18 - Viewing audit logs
- Red Hat OpenShift Container Platform 4.18 - Logging overview
