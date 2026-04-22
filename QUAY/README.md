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


# Runbook — Modifica configurazione LDAP in Red Hat Quay su OpenShift

## Obiettivo

Modificare la configurazione LDAP di **Red Hat Quay** installato su **OpenShift tramite Quay Operator**.

Nel deployment Operator-based, la configurazione di Quay è contenuta nel file:

```text
config.yaml
```

Il file `config.yaml` è salvato dentro una Kubernetes/OpenShift **Secret** referenziata dalla CR:

```text
QuayRegistry.spec.configBundleSecret
```

Il metodo consigliato è:

1. individuare la `QuayRegistry`;
2. recuperare il `configBundleSecret` attuale;
3. estrarre il `config.yaml`;
4. modificarlo;
5. creare una nuova Secret;
6. patchare la `QuayRegistry` per usare la nuova Secret;
7. verificare redeploy e login LDAP;
8. in caso di problema, fare rollback alla Secret precedente.

---

## Prerequisiti

Eseguire i comandi da una macchina dove sia disponibile `oc` e dove si sia già loggati al cluster:

```bash
oc whoami
oc whoami --show-server
```

Verificare di avere permessi sul namespace dove è installato Quay:

```bash
oc get quayregistry -A
```

---

## 1. Individuare namespace e nome della QuayRegistry

```bash
oc get quayregistry -A
```

Esempio output:

```text
NAMESPACE   NAME
quay        quay-registry
```

Impostare le variabili:

```bash
NS=quay
QR=quay-registry
```

Verificare:

```bash
oc get quayregistry "$QR" -n "$NS" -o yaml
```

---

## 2. Recuperare il configBundleSecret attuale

```bash
SECRET=$(oc get quayregistry "$QR" -n "$NS" -o jsonpath='{.spec.configBundleSecret}')
echo "$SECRET"
```

Verificare che la Secret esista:

```bash
oc get secret "$SECRET" -n "$NS"
```

Verificare che contenga `config.yaml`:

```bash
oc get secret "$SECRET" -n "$NS" -o jsonpath='{.data}' | jq keys
```

Output atteso, indicativamente:

```json
[
  "config.yaml"
]
```

---

## 3. Estrarre il config.yaml attuale

Creare una directory di lavoro:

```bash
mkdir -p ~/quay-ldap-change
cd ~/quay-ldap-change
```

Estrarre il file `config.yaml` dalla Secret:

```bash
oc get secret "$SECRET" -n "$NS" \
  -o jsonpath='{.data.config\.yaml}' | base64 -d > config.yaml
```

Creare backup locale:

```bash
cp config.yaml config.yaml.backup.$(date +%Y%m%d-%H%M%S)
```

Verificare il contenuto:

```bash
less config.yaml
```

---

## 4. Modificare il config.yaml

Aprire il file:

```bash
vi config.yaml
```

La configurazione LDAP deve contenere o aggiornare parametri simili ai seguenti.

### Esempio LDAP semplice

```yaml
AUTHENTICATION_TYPE: LDAP

LDAP_URI: "ldap://ldap.example.local"
LDAP_BASE_DN:
  - dc=example
  - dc=local
LDAP_USER_RDN:
  - ou=Users
LDAP_UID_ATTR: uid
LDAP_EMAIL_ATTR: mail
LDAP_ADMIN_DN: "cn=quay-bind,ou=ServiceAccounts,dc=example,dc=local"
LDAP_ADMIN_PASSWD: "password-bind-ldap"
LDAP_ALLOW_INSECURE_FALLBACK: false
LDAP_USER_FILTER: "(memberOf=cn=quay-users,ou=Groups,dc=example,dc=local)"
```

### Esempio LDAPS

```yaml
AUTHENTICATION_TYPE: LDAP

LDAP_URI: "ldaps://ldap.example.local"
LDAP_BASE_DN:
  - dc=example
  - dc=local
LDAP_USER_RDN:
  - ou=Users
LDAP_UID_ATTR: uid
LDAP_EMAIL_ATTR: mail
LDAP_ADMIN_DN: "cn=quay-bind,ou=ServiceAccounts,dc=example,dc=local"
LDAP_ADMIN_PASSWD: "password-bind-ldap"
LDAP_ALLOW_INSECURE_FALLBACK: false
LDAP_USER_FILTER: "(memberOf=cn=quay-users,ou=Groups,dc=example,dc=local)"
```

---

## 5. Validare il file YAML

Metodo con Python:

```bash
python3 - <<'PY'
import yaml
with open("config.yaml") as f:
    yaml.safe_load(f)
print("YAML OK")
PY
```

Se il modulo `yaml` non è disponibile, usare Ruby:

```bash
ruby -e "require 'yaml'; YAML.load_file('config.yaml'); puts 'YAML OK'"
```

In alternativa, se disponibile:

```bash
yq e '.' config.yaml >/dev/null && echo "YAML OK"
```

---

## 6. Creare una nuova Secret con il config.yaml modificato

> Consigliato: creare una nuova Secret invece di modificare direttamente quella esistente.  
> In questo modo il rollback è immediato.

```bash
NEW_SECRET="${QR}-config-bundle-ldap-$(date +%Y%m%d%H%M%S)"

oc create secret generic "$NEW_SECRET" \
  -n "$NS" \
  --from-file=config.yaml=./config.yaml
```

Verificare:

```bash
oc get secret "$NEW_SECRET" -n "$NS"
```

Verificare che la Secret contenga il `config.yaml`:

```bash
oc get secret "$NEW_SECRET" -n "$NS" -o jsonpath='{.data}' | jq keys
```

---

## 7. Patch della QuayRegistry

Applicare la nuova Secret alla `QuayRegistry`:

```bash
oc patch quayregistry "$QR" -n "$NS" --type=merge \
  -p "{\"spec\":{\"configBundleSecret\":\"$NEW_SECRET\"}}"
```

Verificare che la CR punti alla nuova Secret:

```bash
oc get quayregistry "$QR" -n "$NS" \
  -o jsonpath='{.spec.configBundleSecret}{"\n"}'
```

Output atteso:

```text
quay-registry-config-bundle-ldap-YYYYMMDDHHMMSS
```

---

## 8. Monitorare il redeploy

Monitorare i pod:

```bash
oc get pods -n "$NS" -w
```

In un altro terminale, controllare lo stato della `QuayRegistry`:

```bash
oc get quayregistry "$QR" -n "$NS" -o yaml | \
  egrep -i "phase|message|condition|configBundleSecret" -A3 -B3
```

Controllare i Deployment Quay:

```bash
oc get deploy -n "$NS" | grep -i quay
```

Individuare il deployment applicativo:

```bash
APP_DEPLOY=$(oc get deploy -n "$NS" -o name | grep quay-app | head -1)
echo "$APP_DEPLOY"
```

Leggere i log:

```bash
oc logs -n "$NS" "$APP_DEPLOY" --tail=200
```

Filtrare eventuali errori LDAP/autenticazione:

```bash
oc logs -n "$NS" "$APP_DEPLOY" --tail=500 | \
  egrep -i "ldap|auth|bind|user|error|invalid|failed"
```

---

## 9. Test login LDAP

Dopo il redeploy:

1. aprire la UI di Quay;
2. provare login con un utente LDAP autorizzato;
3. verificare eventuali errori nei log.

Comando utile durante il test:

```bash
oc logs -n "$NS" "$APP_DEPLOY" --tail=500 | \
  egrep -i "ldap|auth|bind|user|error|invalid|failed"
```

---

## 10. Rollback immediato

Se il login LDAP non funziona o Quay presenta problemi, tornare alla Secret precedente.

La variabile `$SECRET` contiene il vecchio `configBundleSecret`, recuperato all’inizio.

```bash
oc patch quayregistry "$QR" -n "$NS" --type=merge \
  -p "{\"spec\":{\"configBundleSecret\":\"$SECRET\"}}"
```

Verificare:

```bash
oc get quayregistry "$QR" -n "$NS" \
  -o jsonpath='{.spec.configBundleSecret}{"\n"}'
```

Monitorare il redeploy:

```bash
oc get pods -n "$NS" -w
```

Controllare log:

```bash
oc logs -n "$NS" "$APP_DEPLOY" --tail=300
```

---

## 11. Script unico operativo

> Cambiare solo `NS` e `QR` all’inizio.

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Modifica LDAP Red Hat Quay via Quay Operator
# ============================================================

NS=quay
QR=quay-registry

echo "[INFO] Namespace Quay: $NS"
echo "[INFO] QuayRegistry:   $QR"

echo "[INFO] Recupero configBundleSecret attuale..."
SECRET=$(oc get quayregistry "$QR" -n "$NS" -o jsonpath='{.spec.configBundleSecret}')

if [[ -z "$SECRET" ]]; then
  echo "[ERROR] Impossibile recuperare spec.configBundleSecret dalla QuayRegistry $QR nel namespace $NS"
  exit 1
fi

echo "[INFO] Current configBundleSecret: $SECRET"

WORKDIR="$HOME/quay-ldap-change"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

echo "[INFO] Estraggo config.yaml..."
oc get secret "$SECRET" -n "$NS" \
  -o jsonpath='{.data.config\.yaml}' | base64 -d > config.yaml

BACKUP_FILE="config.yaml.backup.$(date +%Y%m%d-%H%M%S)"
cp config.yaml "$BACKUP_FILE"

echo "[INFO] Backup creato: $WORKDIR/$BACKUP_FILE"
echo "[INFO] Modifica ora il file config.yaml"
echo

vi config.yaml

echo "[INFO] Validazione YAML..."

if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY'
import yaml
with open("config.yaml") as f:
    yaml.safe_load(f)
print("YAML OK")
PY
elif command -v ruby >/dev/null 2>&1; then
  ruby -e "require 'yaml'; YAML.load_file('config.yaml'); puts 'YAML OK'"
elif command -v yq >/dev/null 2>&1; then
  yq e '.' config.yaml >/dev/null && echo "YAML OK"
else
  echo "[WARN] Nessun validatore YAML trovato tra python3/ruby/yq. Procedo senza validazione automatica."
fi

NEW_SECRET="${QR}-config-bundle-ldap-$(date +%Y%m%d%H%M%S)"

echo "[INFO] Creo nuova Secret: $NEW_SECRET"

oc create secret generic "$NEW_SECRET" \
  -n "$NS" \
  --from-file=config.yaml=./config.yaml

echo "[INFO] Patch QuayRegistry con nuova Secret..."

oc patch quayregistry "$QR" -n "$NS" --type=merge \
  -p "{\"spec\":{\"configBundleSecret\":\"$NEW_SECRET\"}}"

echo "[INFO] Nuovo configBundleSecret applicato:"
oc get quayregistry "$QR" -n "$NS" \
  -o jsonpath='{.spec.configBundleSecret}{"\n"}'

echo
echo "[INFO] Pod Quay:"
oc get pods -n "$NS"

echo
echo "[INFO] Per monitorare il redeploy:"
echo "oc get pods -n $NS -w"

echo
echo "[INFO] Per rollback:"
echo "oc patch quayregistry $QR -n $NS --type=merge -p '{\"spec\":{\"configBundleSecret\":\"$SECRET\"}}'"
```

---

## 12. Comandi rapidi di troubleshooting

### Vedere la Secret attualmente usata

```bash
oc get quayregistry "$QR" -n "$NS" \
  -o jsonpath='{.spec.configBundleSecret}{"\n"}'
```

### Estrarre e vedere il config.yaml attivo

```bash
ACTIVE_SECRET=$(oc get quayregistry "$QR" -n "$NS" -o jsonpath='{.spec.configBundleSecret}')

oc get secret "$ACTIVE_SECRET" -n "$NS" \
  -o jsonpath='{.data.config\.yaml}' | base64 -d | less
```

### Cercare solo la parte LDAP

```bash
ACTIVE_SECRET=$(oc get quayregistry "$QR" -n "$NS" -o jsonpath='{.spec.configBundleSecret}')

oc get secret "$ACTIVE_SECRET" -n "$NS" \
  -o jsonpath='{.data.config\.yaml}' | base64 -d | \
  egrep -i "AUTHENTICATION_TYPE|LDAP_"
```

### Controllare i pod Quay

```bash
oc get pods -n "$NS" -o wide
```

### Controllare deployment Quay

```bash
oc get deploy -n "$NS" | grep -i quay
```

### Controllare log applicativi

```bash
APP_DEPLOY=$(oc get deploy -n "$NS" -o name | grep quay-app | head -1)

oc logs -n "$NS" "$APP_DEPLOY" --tail=300
```

### Cercare errori LDAP

```bash
oc logs -n "$NS" "$APP_DEPLOY" --tail=500 | \
  egrep -i "ldap|auth|bind|user|error|invalid|failed"
```

---

## 13. Note operative importanti

### Non modificare i pod direttamente

Non modificare file dentro i pod Quay, perché:

- i pod possono essere ricreati;
- la configurazione è gestita dall’Operator;
- la sorgente corretta è il `configBundleSecret`.

### Preferire nuova Secret invece di edit della Secret esistente

È possibile modificare direttamente la Secret, ma è più sicuro creare una nuova Secret e patchare la `QuayRegistry`.

Vantaggi:

- rollback immediato;
- storico più chiaro;
- minore rischio operativo.

### Attenzione a utenti locali già esistenti

Se Quay aveva già utenti locali e si passa ad autenticazione LDAP, verificare eventuali conflitti di username.

### Attenzione a LDAPS e CA

Se si usa `ldaps://`, verificare che Quay si fidi della CA del server LDAP/AD.

In caso di CA custom, potrebbe essere necessario aggiungere la CA nel bundle di configurazione, in base alla configurazione già presente del registry.

---

## 14. Riferimenti utili

- Red Hat Quay Operator su OpenShift:
  - https://docs.redhat.com/en/documentation/red_hat_quay/
- Configurazione Red Hat Quay:
  - https://docs.redhat.com/en/documentation/red_hat_quay/
- Project Quay documentation:
  - https://docs.projectquay.io/



