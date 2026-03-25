
# 📦 MinIO su RHEL/Rocky 9 + OADP Backup & Restore su OpenShift

Guida completa per installare **MinIO** su VM RHEL/Rocky 9 (binario o container Podman con systemd)
e configurare **OpenShift API for Data Protection (OADP)** per backup e restore di:
- Namespace
- PV / PVC
- CRD

Senza ACM, focalizzata su OCP.

---

## 📑 Indice
1. Requisiti
2. MinIO come binario
3. MinIO come container (Podman)
4. Podman → systemd
5. Configurazione MinIO (bucket)
6. Installazione OADP
7. Configurazione OADP + MinIO
8. Backup via CRD
9. Restore via CRD
10. Debug & troubleshooting

---

## 1. Requisiti

- VM RHEL 9 o Rocky 9 (root)
- OpenShift Container Platform 4.x
- `oc` configurato
- Porte 9000 / 9001 raggiungibili dal cluster

---

## 2. MinIO come binario

```bash
wget https://dl.min.io/server/minio/release/linux-amd64/minio
chmod +x minio
mv minio /usr/local/bin/minio

mkdir -p /opt/minio/data

export MINIO_ROOT_USER=minioroot
export MINIO_ROOT_PASSWORD=SuperStrongPass123!

minio server /opt/minio/data --address ":9000" --console-address ":9001"
```

---

## 3. MinIO come container (Podman)

```bash
dnf install @container-tools -y

podman pull minio/minio

podman run -d --name minio   -p 9000:9000 -p 9001:9001   -e MINIO_ROOT_USER=minioroot   -e MINIO_ROOT_PASSWORD=SuperStrongPass123!   -v /opt/minio/data:/data   minio/minio server /data --console-address ":9001"
```

---

## 4. Podman → systemd

```bash
podman generate systemd --name minio --files --new
mv container-minio.service /etc/systemd/system/

systemctl daemon-reexec
systemctl daemon-reload
systemctl enable --now container-minio
systemctl status container-minio
```

Opzionale hardening:

```ini
[Service]
Restart=always
RestartSec=5
LimitNOFILE=65536
```

---

## 5. Configurazione MinIO (bucket)

```bash
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
mv mc /usr/local/bin/mc

mc alias set local http://<MINIO_IP>:9000 minioroot SuperStrongPass123!
mc mb local/oadp-backups
```

---

## 6. Installazione OADP

- OperatorHub → OpenShift API for Data Protection
- Namespace: `openshift-adp`

Verifica:

```bash
oc get pods -n openshift-adp
```

---

## 7. Configurazione OADP + MinIO

### Credenziali

```ini
[default]
aws_access_key_id=minioroot
aws_secret_access_key=SuperStrongPass123!
```

```bash
oc create secret generic cloud-credentials   -n openshift-adp   --from-file=cloud=./credentials-minio
```

### DataProtectionApplication

```yaml
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: oadp-minio
  namespace: openshift-adp
spec:
  backupLocations:
    - velero:
        provider: aws
        objectStorage:
          bucket: oadp-backups
          prefix: velero
        config:
          s3Url: http://<MINIO_IP>:9000
          s3ForcePathStyle: "true"
          region: us-east-1
        credential:
          name: cloud-credentials
          key: cloud
  configuration:
    velero:
      defaultPlugins:
        - aws
    restic:
      enable: true
```

---

## 8. Backup via CRD

### Namespace + PV/PVC

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: demo-backup
  namespace: openshift-adp
spec:
  includedNamespaces:
    - demo
  snapshotVolumes: true
  defaultVolumesToRestic: true
  ttl: 168h
```

### Solo CRD

```yaml
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: crd-backup
  namespace: openshift-adp
spec:
  includedResources:
    - customresourcedefinitions.apiextensions.k8s.io
```

---

## 9. Restore via CRD

### Restore completo

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: demo-restore
  namespace: openshift-adp
spec:
  backupName: demo-backup
```

### Restore senza PV

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: demo-nopv
  namespace: openshift-adp
spec:
  backupName: demo-backup
  restorePVs: false
```

### Namespace remap

```yaml
apiVersion: velero.io/v1
kind: Restore
metadata:
  name: demo-remap
  namespace: openshift-adp
spec:
  backupName: demo-backup
  namespaceMapping:
    demo: demo-restored
```

---

## 10. Debug

```bash
oc describe backup demo-backup -n openshift-adp
oc describe restore demo-restore -n openshift-adp

oc logs deploy/velero -n openshift-adp
```

---
