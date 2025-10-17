
# 🧭 OpenShift Cluster Migration Guide (MTC + MinIO) — Online & Offline

Questa guida descrive come migrare applicazioni, namespace e persistent volumes tra due cluster **OpenShift 4.x** usando **Migration Toolkit for Containers (MTC)**.  
Copre entrambi gli scenari:
1. **Migrazione Offline (con MinIO/S3)** → quando i due cluster NON hanno connettività diretta.
2. **Migrazione Online (cluster connessi)** → quando i due cluster possono comunicare tra loro.

---

## 📘 1. Architettura Generale

### Scenario A — Migrazione Offline (con MinIO/S3)

```
+-----------------------+        +-------------------+        +-----------------------+
|   OpenShift Source    |        |     MinIO/S3      |        |   OpenShift Target    |
| (es. OCP 4.13 - DC1)  | <----> |  Object Storage   | <----> | (es. OCP 4.18 - DC2)  |
|  mig-controller       |        |  (Persistente)    |        |  mig-controller       |
+-----------------------+        +-------------------+        +-----------------------+
```

### Scenario B — Migrazione Online (cluster connessi)

```
+-----------------------+
|   OpenShift Source    |
| (es. OCP 4.13 - DC1)  |
|  mig-controller       |
+----------┬------------+
           │ TCP/443 (API)
           ▼
+-----------------------+
|   OpenShift Target    |
| (es. OCP 4.18 - DC2)  |
|  mig-controller       |
+-----------------------+
```

---

## 🧩 2. Prerequisiti comuni

| Requisito | Descrizione |
|------------|-------------|
| OpenShift | Versione 4.10+ (consigliato target ≥4.18) |
| Autorizzazioni | Cluster-admin su entrambi i cluster |
| Network | DNS e risoluzione reciproca per API, se online |
| Storage | Accesso PV compatibile o S3 compatibile |
| Tool | `oc`, `helm`, `kubectl`, `mtc` CLI opzionale |

---

## ☁️ 3. Installazione di MinIO (per scenario Offline)

MinIO è uno storage S3-compatibile che permette di salvare i dati esportati da MTC.  
Può essere installato **su una VM dedicata** o **direttamente nel cluster OpenShift sorgente o target**.

### Opzione 1 — Deploy su VM esterna

1. Scarica MinIO:
```bash
wget https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
./minio server /data --console-address ":9001"
```

2. Crea utente e credenziali:
```bash
export MINIO_ROOT_USER=admin
export MINIO_ROOT_PASSWORD=StrongPassword123
```

3. Espone le porte TCP:
- 9000 → API S3  
- 9001 → Console Web

4. Configura volume persistente `/data` su disco dedicato (consigliato ≥ 100 GiB).

### Opzione 2 — Deploy su OpenShift

```bash
oc new-project minio
oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-pv
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: quay.io/minio/minio:latest
        args: ["server", "/data"]
        env:
        - name: MINIO_ROOT_USER
          value: "admin"
        - name: MINIO_ROOT_PASSWORD
          value: "StrongPassword123"
        ports:
        - containerPort: 9000
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: minio-pv
---
apiVersion: v1
kind: Service
metadata:
  name: minio
spec:
  ports:
    - port: 9000
      targetPort: 9000
  selector:
    app: minio
EOF
```

Accedi all’interfaccia web tramite:
```
https://minio.<route>.apps.<cluster-domain>:9000
```

---

## 🛰️ 4. Installazione del Migration Toolkit for Containers (MTC)

### Metodo 1 — via OperatorHub

1. Accedi al cluster sorgente.  
2. Vai su **Operators → OperatorHub**.  
3. Cerca **Migration Toolkit for Containers**.  
4. Installa nella namespace `openshift-migration`.  
5. Conferma la creazione dei CRD `MigrationController`, `MigPlan`, `MigStorage`, `MigCluster`, `MigMigration`.

### Metodo 2 — via CLI

```bash
oc new-project openshift-migration
oc apply -f https://raw.githubusercontent.com/konveyor/mig-operator/master/deploy/olm-catalog/mig-operator.yaml
```

---

## 🔐 5. Prerequisiti di rete e firewall

| Direzione | Porta | Descrizione |
|------------|-------|-------------|
| Source → Target API | TCP/443 | Comunicazione tra cluster (solo per online) |
| Source → MinIO | TCP/9000 | Upload dei dati esportati |
| Target → MinIO | TCP/9000 | Download dei dati durante import |
| API OpenShift | TCP/6443 | Accesso API standard |
| Registry (opzionale) | TCP/5000-6000 | Se si trasferiscono immagini container interne |

---

## 🔄 6. Flusso di migrazione

### Scenario Offline (con MinIO)

1. **Configura Storage (MinIO)** → definisci `MigStorage` CRD con endpoint S3.  
2. **Registra cluster sorgente e target** → `MigCluster` CRD.  
3. **Crea un MigPlan** → seleziona namespaces e PVC da migrare.  
4. **Esegui Backup** → MTC esporta YAML, PVC, e dati su MinIO.  
5. **Esegui Restore sul target** → MTC importa risorse e PV nel nuovo cluster.  

```
[Source OCP 4.13] → [MinIO] → [Target OCP 4.18]
```

### Scenario Online (cluster connessi)

1. **Registra entrambi i cluster** tramite API reciproche.  
2. **Crea un MigPlan condiviso** → namespace, PV, image streams.  
3. **Lancia la migrazione diretta** → MTC copia risorse e PV in tempo reale.  
4. **Convalida e test finali** → verifica pod e deployment sul target.

```
[Source OCP 4.13] ───MTC API───> [Target OCP 4.18]
```

---

## 🧪 7. Post-migrazione e validazioni

- Verifica che i namespace, secret, configmap e deployment siano coerenti.  
- Controlla i PVC ricreati e i mountPath corretti.  
- Esegui un **rollout restart** per forzare i pod a riavviarsi.  
- Aggiorna le route sul F5 per puntare al nuovo cluster.

---

## 🧰 8. Troubleshooting

| Sintomo | Possibile causa | Soluzione |
|----------|----------------|------------|
| Migrazione bloccata su “Backup running” | Mancata connessione MinIO o credenziali errate | Verifica `MigStorage` |
| Errore TLS | Certificato S3 non trusted | Usa opzione `insecure: true` nel CR |
| PVC non ripristinati | PV non compatibili tra cluster | Assicurati che lo storage class esista sul target |
| Oggetti duplicati | Migrazione parziale o doppia | Rimuovi risorse e riesegui `restore` |

---

## 🧾 9. Conclusione

- **Scenario Offline:** ideale per datacenter isolati. Backup su MinIO, restore sul target.  
- **Scenario Online:** più rapido, ma richiede rete sicura e stabile tra cluster.  
- Entrambi supportati nativamente da MTC e gestibili via console o CLI.  
- Consigliato testare una migrazione di un singolo namespace prima del cutover finale.

---
