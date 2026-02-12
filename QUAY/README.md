# RUNBOOK – Backup Red Hat Quay (Operator + rclone)

---

## 1. Placeholder

```bash
export QUAY_NAMESPACE=registry
oc get quayregistry -A
export QUAY_REGISTRY_NAME=$(oc get quayregistry -n $QUAY_NAMESPACE -o jsonpath='{.items[0].metadata.name}')
export QUAY_OPERATOR_NAMESPACE=$(oc get pods -A | awk '/quay-operator/ {print $1; exit}')
export QUAY_POD_NAME=$(oc get pod -n $QUAY_NAMESPACE -l app=quay -o jsonpath='{.items[0].metadata.name}')
export POSTGRES_POD_NAME=$(oc get pod -n $QUAY_NAMESPACE -l quay-component=postgres -o jsonpath='{.items[0].metadata.name}')
export DB_NAME=$(oc exec -n $QUAY_NAMESPACE $QUAY_POD_NAME -- grep '^DB_URI' /conf/stack/config.yaml | awk -F"/" '{print $4}')
```

---

## 2. Backup configurazione

```bash
oc get quayregistry $QUAY_REGISTRY_NAME -n $QUAY_NAMESPACE -o yaml > quay-registry.yaml
yq -i '
  del(
    .status,
    .metadata.creationTimestamp,
    .metadata.finalizers,
    .metadata.generation,
    .metadata.resourceVersion,
    .metadata.uid,
    .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration"
  )
' quay-registry.yaml

oc get secret -n $QUAY_NAMESPACE ${QUAY_REGISTRY_NAME}-quay-registry-managed-secret-keys -o yaml > managed_secret_keys.yaml
yq -i '
  .metadata |= {
    "name": .name,
    "namespace": .namespace
  }
' managed_secret_keys.yaml

oc get secret -n $QUAY_NAMESPACE $(oc get quayregistry $QUAY_REGISTRY_NAME -n $QUAY_NAMESPACE -o jsonpath='{.spec.configBundleSecret}') -o yaml > config-bundle.yaml
oc exec -n $QUAY_NAMESPACE $QUAY_POD_NAME -- cat /conf/stack/config.yaml > quay_config.yaml
```

---

## 3. Scale down

Impostare repliche a 0 per quay / mirror / clair (Operator ≥ 3.7)

```bash

oc patch quayregistry registry -n ns --type=merge -p '
spec:
  components:
  - kind: horizontalpodautoscaler
    managed: false
  - kind: quay
    managed: true
    overrides:
      replicas: 0
  - kind: clair
    managed: true
    overrides:
      replicas: 0
  - kind: mirror
    managed: true
    overrides:
      replicas: 0
'

```

---

## 4. Backup database

```bash
oc exec -n $QUAY_NAMESPACE $POSTGRES_POD_NAME -- pg_dump -C $DB_NAME > quay-db-backup.sql
```

---

## 5. Backup blob con rclone

```bash
export AWS_ACCESS_KEY_ID=$(oc get secret -l app=noobaa -n $QUAY_NAMESPACE -o jsonpath='{.items[0].data.AWS_ACCESS_KEY_ID}' | base64 -d)
export AWS_SECRET_ACCESS_KEY=$(oc get secret -l app=noobaa -n $QUAY_NAMESPACE -o jsonpath='{.items[0].data.AWS_SECRET_ACCESS_KEY}' | base64 -d)
export S3_ENDPOINT=https://$(oc get route s3 -n openshift-storage -o jsonpath='{.spec.host}')
export BUCKET_NAME=$(oc get cm -l app=noobaa -n $QUAY_NAMESPACE -o jsonpath='{.items[0].data.BUCKET_NAME}')

rclone config create quay-noobaa s3 provider Other env_auth false access_key_id $AWS_ACCESS_KEY_ID secret_access_key $AWS_SECRET_ACCESS_KEY endpoint $S3_ENDPOINT region us-east-1

mkdir -p blobs
rclone sync quay-noobaa:$BUCKET_NAME blobs --progress --checksum --no-check-certificate
```

---

## 6. Scale up e verifica

```bash
oc wait quayregistry $QUAY_REGISTRY_NAME --for=condition=Available=true -n $QUAY_NAMESPACE
```

---

## Backup completato
RIF : https://docs.redhat.com/en/documentation/red_hat_quay/3.16/html/red_hat_quay_operator_features/backing-up-and-restoring-intro
