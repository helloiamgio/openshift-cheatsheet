---

# rclone — Cheat Sheet Definitivo (OCP/ODF friendly)

> **Scopo**: guida pratica e compatta all'uso di `rclone` con esempi pronti all’uso. In coda trovi la sezione dedicata a **S3 su ODF/NooBaa in OpenShift** (recupero endpoint/bucket e configurazione). Questa pagina è pubblicabile direttamente su **GitHub Pages**.

---

## Indice
- [Installazione e help rapido](#installazione-e-help-rapido)
- [Concetti chiave](#concetti-chiave)
- [Gestione remoti](#gestione-remoti)
- [Listing e ispezione](#listing-e-ispezione)
- [Copia e sincronizzazione](#copia-e-sincronizzazione)
- [Mirroring, verifiche e checksum](#mirroring-verifiche-e-checksum)
- [Filtri (include/exclude) e selettori](#filtri-includeexclude-e-selettori)
- [Prestazioni: parallelismo, banda, chunking](#prestazioni-parallelismo-banda-chunking)
- [Riprese, retry e robustezza](#riprese-retry-e-robustezza)
- [Crittografia (remote `crypt`)](#crittografia-remote-crypt)
- [Mount, serve e link utili](#mount-serve-e-link-utili)
- [Ambiente, config e sicurezza](#ambiente-config-e-sicurezza)
- [Troubleshooting](#troubleshooting)
- [Appendice — ODF/NooBaa su OpenShift (S3)](#appendice--odfnoobaa-su-openshift-s3)

---

## Installazione e help rapido

```bash
# Verifica versione
rclone version

# Manuale built-in
rclone help           # indice comandi
rclone help config    # help del sottocomando

# Autocompletamento (bash, zsh)
rclone genautocomplete bash | sudo tee /etc/bash_completion.d/rclone
source ~/.bashrc
```

---

## Concetti chiave
- **Remote**: un endpoint/storage configurato (es. `odf-quay-ac`), referenziato come `remote:` o `remote:bucket/path`.
- **Bucket**: per S3 è il livello top (equivalente a directory root del remote).
- **Oggetti/Path**: file e directory virtuali all’interno del bucket.

---

## Gestione remoti

```bash
# Wizard configurazione
rclone config

# Crea un remote S3 non interattivo (esempio generico)
rclone config create my-s3 s3 \
  provider=Other \
  endpoint=https://s3.example.local \
  access_key_id="$AWS_ACCESS_KEY_ID" \
  secret_access_key="$AWS_SECRET_ACCESS_KEY" \
  env_auth=false \
  force_path_style=true \
  acl=private

# Mostra i remoti esistenti
rclone listremotes

# Test connessione (debug SSL off se necessario)
rclone lsd my-s3: --no-check-certificate -vv
```

> **Tip**: con S3 self‑hosted (NooBaa/ODF, MinIO, Ceph RGW) spesso serve `force_path_style=true`.

---

## Listing e ispezione

```bash
# Elenco bucket (S3)
rclone lsd my-s3:

# Elenco contenuti di un bucket o path
rclone ls   my-s3:bucket
rclone lsl  my-s3:bucket/prefix/
rclone lsd  my-s3:bucket             # solo directory
rclone tree my-s3:bucket/prefix/     # struttura ad albero

# Stat di un singolo oggetto
rclone about my-s3:bucket
rclone md5sum my-s3:bucket/prefix/
```

---

## Copia e sincronizzazione

```bash
# Copia (non cancella differenze lato destinazione)
rclone copy my-s3:bucket/prefix/ ./dest/ \
  --progress --transfers 16 --checkers 32

# Sincronizzazione (mirror: aggiunge/aggiorna/cancella)
rclone sync my-s3:bucket/prefix/ ./dest/ \
  --progress --transfers 16 --checkers 32

# Dry-run prima di eseguire
rclone sync my-s3:bucket ./dest --dry-run --progress

# Reverse (da locale a S3)
rclone sync ./src/ my-s3:bucket/prefix/ --progress

# Rclone come rsync (solo cambiamenti, preserva timestamp ove supportato)
rclone copyto ./file.bin my-s3:bucket/file.bin --progress
```

---

## Mirroring, verifiche e checksum

```bash
# Confronto bidirezionale (senza modifiche)
rclone check my-s3:bucketA/ my-s3:bucketB/ \
  --one-way --size-only

# Verifica tra remoto e locale
rclone check my-s3:bucket/ ./path/ --checksum --size-only

# Genera hash (se supportato dal backend)
rclone md5sum my-s3:bucket/prefix/
rclone sha1sum my-s3:bucket/prefix/
```

> **Nota**: non tutti i backend espongono gli stessi hash; con S3 l’ETag non sempre è un MD5 quando c’è multipart upload.

---

## Filtri (include/exclude) e selettori

```bash
# Escludi alcune estensioni
rclone sync my-s3:bucket ./dest \
  --exclude "*.tmp" --exclude "*.bak"

# Includi solo alcuni pattern
rclone copy my-s3:bucket ./dest \
  --include "*.jpg" --include "*.png" --exclude "*"

# Filtri da file
rclone sync my-s3:bucket ./dest --filter-from filter.txt

# Esempio filter.txt
+ *.log
- *.gz
- .*                # ignora file nascosti
```

---

## Prestazioni: parallelismo, banda, chunking

```bash
# Regola parallelismo
--transfers 16   # upload/download concorrenti
--checkers 32    # processi di listing/check paralleli

# Limita banda
--bwlimit 50M    # 50 MB/s (può essere schedulato: 08:00,10M 20:00,off)

# Multipart/chunk (S3): talvolta utile per oggetti molto grandi
--s3-upload-concurrency 8
--s3-chunk-size 64M
```

---

## Riprese, retry e robustezza

```bash
# Retry e backoff
--retries 10 --low-level-retries 20 --retries-sleep 5s

# Timeouts
--timeout 5m --contimeout 30s

# Ripartenza da interruzioni
--immutable         # non sovrascrivere file immutabili
--update            # copia solo se source più recente
```

---

## Crittografia (remote `crypt`)

```bash
# Crea un layer crittografico sopra un remote esistente
rclone config create my-s3-crypt crypt \
  remote=my-s3:bucket/prefix \
  filename_encryption=standard \
  directory_name_encryption=true \
  password=**** \
  password2=****    # opzionale per salting

# Uso del remote crittografato
rclone sync ./data/ my-s3-crypt: --progress
```

---

## Mount, serve e link utili

```bash
# Monta un remote su filesystem (FUSE)
sudo rclone mount my-s3:bucket /mnt/s3 \
  --daemon --allow-other --dir-cache-time 1h

# Esponi via HTTP/WebDAV/SFTP
rclone serve http   my-s3:bucket --addr :8080
rclone serve webdav my-s3:bucket --addr :8081 --user u --pass p
rclone serve sftp   my-s3:bucket --addr :2222 --user u --pass p
```

---

## Ambiente, config e sicurezza

```bash
# Path del file di configurazione (default ~/.config/rclone/rclone.conf)
rclone config file

# Esempio di rclone.conf (S3 generico)
[s3-odf]
 type = s3
 provider = Other
 endpoint = https://s3.example.local
 access_key_id = <ACCESS_KEY>
 secret_access_key = <SECRET_KEY>
 env_auth = false
 force_path_style = true
 acl = private

# Variabili d'ambiente utili
export RCLONE_CONFIG=/path/custom/rclone.conf
export RCLONE_PROGRESS=true
export AWS_S3_FORCE_PATH_STYLE=true     # per backend S3 compatibili
```

> **SSL**: in ambienti con CA interna preferire `--ca-cert /path/ca.crt` (o `--ca-bundle` dove applicabile) a `--no-check-certificate`.

---

## Troubleshooting

```bash
# Verbosità
-vv                      # log dettagliato
--log-file rclone.log    # salva log

# Test connessione e SSL
rclone lsd my-s3: -vv --no-check-certificate

# Identificare perché un file non viene trasferito
--dry-run --dump filters --dump headers --dump bodies

# Diagnostic dei limiti di API o throttling
--stats 10s --stats-one-line --retries 20
```

---

## Appendice — ODF/NooBaa su OpenShift (S3)

Questa sezione mostra come **recuperare endpoint e bucket** di NooBaa/ODF su OpenShift, **configurare un remote rclone** e **sincronizzare dati**.

### 1) Recupera endpoint S3 (Route di NooBaa)

```bash
# Namespace tipico di ODF/NooBaa
ODF_NS=openshift-storage

# Hostname dell'endpoint S3 (HTTPS)
S3_HOST=$(oc get route s3 -n "$ODF_NS" -o jsonpath='{.spec.host}')
S3_ENDPOINT="https://$S3_HOST"
echo "$S3_ENDPOINT"
```

Se l'ambiente usa un certificato interno, scarica la CA e usa `--ca-cert`/`--no-check-certificate` all’occorrenza.

### 2) Recupera il nome del bucket (da Quay o da NooBaa)

**Da ConfigMap di Quay** (se etichettata):

```bash
QUAY_NS=<quay-namespace>
BUCKET=$(oc get cm -l app=noobaa -n "$QUAY_NS" -o jsonpath='{.items[0].data.BUCKET_NAME}')
echo "$BUCKET"
```

**Oppure** elenca i bucket visibili con le credenziali S3:

```bash
# Una volta configurato il remote (vedi step 3), puoi fare
rclone lsd odf-s3:
```

### 3) Configura un remote rclone per ODF/NooBaa (S3)

**Via CLI non interattiva**:

```bash
# Prepara le credenziali (accoppiate a un Account/AccessKey di NooBaa)
export AWS_ACCESS_KEY_ID=<ACCESS_KEY>
export AWS_SECRET_ACCESS_KEY=<SECRET_KEY>

# Crea remote S3 per ODF
rclone config create odf-s3 s3 \
  provider=Other \
  endpoint="$S3_ENDPOINT" \
  access_key_id="$AWS_ACCESS_KEY_ID" \
  secret_access_key="$AWS_SECRET_ACCESS_KEY" \
  env_auth=false \
  force_path_style=true \
  acl=private

# Verifica (disabilita verifica certificato se la CA non è trustata)
rclone lsd odf-s3: --no-check-certificate -vv
```

**Via wizard interattivo** (`rclone config`):
- **Storage**: `s3`
- **Provider**: `Other` (o `Ceph`/`Minio`)
- **Endpoint**: `https://<route s3 di ODF>`
- **Access Key / Secret**: coppia di NooBaa
- **Location constraint**: vuoto o default
- **ACL**: `private`
- **Path style**: `true`
- **Edit advanced**: di solito `no`
- **Use auto config**: `no`

### 4) Esempi operativi (Quay, backup/restore)

**Elenca i bucket (individua quello di Quay)**
```bash
rclone lsd odf-s3: --no-check-certificate
```

**Sincronizza il bucket di Quay in locale (remote reale dell'utente)**
```bash
# Esempio con il tuo remote e bucket
rclone sync odf-quay-ac:quay-datastore-b013ec9d-f471-426b-9137-e97d05a66893 ./blobs \
  --no-check-certificate --progress
```

**Restore da locale verso il bucket**
```bash
rclone sync ./blobs odf-quay-ac:quay-datastore-b013ec9d-f471-426b-9137-e97d05a66893 \
  --no-check-certificate --progress --checksum
```

**Consigli**
- Imposta `AWS_S3_FORCE_PATH_STYLE=true` se noti problemi di addressing.
- Preferisci `--ca-cert /path/ca.crt` quando possibile, evita `--no-check-certificate` in produzione.
- Usa `--dry-run` e `--log-level INFO` prima dei job reali.

---

### Mappatura rapida con AWS CLI (per riferimento)

| Operazione | rclone | aws cli |
|---|---|---|
| Listing bucket | `rclone lsd s3:` | `aws s3 ls` |
| Listing path | `rclone ls s3:bucket/prefix/` | `aws s3 ls s3://bucket/prefix/` |
| Copy (one-way) | `rclone copy src dst` | `aws s3 cp --recursive` |
| Sync (mirror) | `rclone sync src dst` | `aws s3 sync` |
| Compare/check | `rclone check a b` | `aws s3 sync --dryrun` + confronti |

---

### Avvertenze
- Su backend S3 compatibili l’ETag non equivale sempre all’MD5 (multipart).
- Valuta versioning, retention e object‑lock lato bucket se richiesti dal compliance.
- Verifica i limiti di dimensione e parallelismo del tuo endpoint S3.

---

**Maintainer note**: aggiorna esempi di namespace/route/bucket secondo il tuo cluster. PR benvenute.
