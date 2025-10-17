# Migrazione OpenShift tra Datacenter con MTC e MinIO (Offline)

## 🧩 Scenario
Migrazione di un cluster **OpenShift 4.13 (vSphere IPI)** verso **OpenShift 4.18** in un **nuovo datacenter**, senza connettività diretta tra i due ambienti.  
La migrazione avviene tramite **Migration Toolkit for Containers (MTC)** utilizzando **MinIO** come backend S3 locale per i backup applicativi e dei volumi persistenti.

---

## ⚙️ Architettura generale

```text
DATACENTER VECCHIO (OCP 4.13)
 ├─ Cluster OpenShift 4.13
 │   ├─ MTC Operator + Velero
 │   └─ MinIO (S3) → bucket: mtc-backup
 │        └─ Salva i backup MTC su PVC locale o NFS
 │
 └──> [Trasferimento offline del bucket (rsync, HDD, ecc.)]
 
DATACENTER NUOVO (OCP 4.18)
 ├─ Cluster OpenShift 4.18
 │   ├─ MTC Operator + Velero
 │   └─ MinIO (S3) → bucket copiato dal vecchio DC
 │
 └──> Ripristino risorse applicative e PV tramite MTC
 
[F5 switch del traffico verso il nuovo cluster]
```

---

## 🧱 Componenti principali

| Componente | Descrizione |
|-------------|-------------|
| **MTC (Migration Toolkit for Containers)** | Tool ufficiale Red Hat per migrazione applicazioni e PV tra cluster OpenShift |
| **Velero** | Strumento di backup/restore usato da MTC |
| **MinIO** | Server object storage compatibile S3 usato per salvare i backup |
| **F5** | Bilanciatore per lo switch del traffico verso il nuovo datacenter |

---

## 🧰 Installazione di MinIO (cluster sorgente e destinazione)

### 1️⃣ Namespace dedicato

```bash
oc new-project openshift-migration
```

### 2️⃣ PersistentVolumeClaim per MinIO

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: minio-pvc
  namespace: openshift-migration
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 200Gi
  storageClassName: nfs-storage
```

> 💡 La dimensione del PVC deve essere ~1.2× la dimensione totale dei PV da migrare.

### 3️⃣ Deployment MinIO

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: openshift-migration
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
        args:
        - server
        - /data
        env:
        - name: MINIO_ACCESS_KEY
          value: "admin"
        - name: MINIO_SECRET_KEY
          value: "password"
        ports:
        - containerPort: 9000
        volumeMounts:
        - name: minio-data
          mountPath: /data
      volumes:
      - name: minio-data
        persistentVolumeClaim:
          claimName: minio-pvc
```

### 4️⃣ Service MinIO

```yaml
apiVersion: v1
kind: Service
metadata:
  name: minio-service
  namespace: openshift-migration
spec:
  ports:
  - port: 9000
    targetPort: 9000
  selector:
    app: minio
```

### 5️⃣ (Facoltativo) Route MinIO

```yaml
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: minio
  namespace: openshift-migration
spec:
  to:
    kind: Service
    name: minio-service
  port:
    targetPort: 9000
  tls:
    termination: edge
```

---

## 🪣 Configurazione Velero/MTC per MinIO

### Secret per credenziali S3

```bash
oc create secret generic cloud-credentials   -n openshift-migration   --from-literal=cloud=aws_access_key_id=admin,aws_secret_access_key=password
```

### BackupStorageLocation

```yaml
apiVersion: velero.io/v1
kind: BackupStorageLocation
metadata:
  name: minio-bsl
  namespace: openshift-migration
spec:
  provider: aws
  objectStorage:
    bucket: mtc-backup
  config:
    region: minio
    s3ForcePathStyle: "true"
    s3Url: http://minio-service.openshift-migration.svc:9000
  credential:
    name: cloud-credentials
    key: cloud
```

---

## 🚀 Flusso di migrazione MTC (offline)

1. **Nel cluster sorgente (OCP 4.13)**  
   - Installa MTC (Migration Toolkit for Containers Operator).  
   - Configura Velero con il backend MinIO locale.  
   - Esegui backup dei namespace da migrare:

     ```bash
     oc -n openshift-migration create migrationbackup mig-backup        --spec-backup-name=mybackup        --spec-backup-namespaces="app1,app2"
     ```

2. **Esporta il bucket MinIO**  
   Da VM esterna o pod MinIO:

   ```bash
   mc alias set local http://localhost:9000 admin password
   mc mirror local/mtc-backup /mnt/export/minio-backup
   ```

   Copia `/mnt/export/minio-backup` nel nuovo DC (rsync, HDD, ecc.).

3. **Nel cluster destinazione (OCP 4.18)**  
   - Installa MTC e Velero.  
   - Configura un MinIO locale e **copia dentro il bucket** esportato.  
   - Crea un BackupStorageLocation puntando a quel MinIO.  
   - Esegui restore:

     ```bash
     oc -n openshift-migration create migrationrestore mig-restore        --spec-restore-name=myrestore        --spec-backup-name=mybackup
     ```

4. **Verifica e test**  
   - Controlla che i Pod siano Running.  
   - Aggiorna ingress, route, e servizi.  

5. **Switch F5**  
   - Ridirigi il traffico sul nuovo cluster (ingress 4.18).  
   - Mantieni il vecchio cluster in read-only per sicurezza.

---

## 💡 Note importanti

- MTC 1.10 (OCP 4.18) è **retrocompatibile** con backup da MTC 1.8 (OCP 4.13).
- MinIO deve avere spazio ≥ dimensione PV da migrare × 1.2.
- Nessuna connessione diretta tra DC richiesta: il bucket viene copiato offline.
- I backup MTC sono applicativi: Deployment, Secret, ConfigMap, PV inclusi.

---

## 🧾 Risorse utili

- [Red Hat MTC Documentation](https://access.redhat.com/documentation/en-us/migration_toolkit_for_containers/)
- [Velero Project](https://velero.io)
- [MinIO Documentation](https://min.io/docs/minio/linux/index.html)
