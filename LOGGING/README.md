# OpenShift Logging 6.x con LokiStack

> **Target**: amministratori OpenShift che vogliono capire davvero come funziona OpenShift Logging 6.x, come si installa, quali CRD contano, come leggere e scrivere le Custom Resource, come ridurre il volume dei log, come fare tuning su Loki e come verificare che tutto sia corretto.
>
> **Versione di riferimento**: contenuti allineati alla documentazione ufficiale **Red Hat OpenShift Logging 6.4** e alla relativa documentazione di installazione/configurazione disponibile a oggi.

---

## Indice

1. [Obiettivo del corso](#1-obiettivo-del-corso)
2. [Come ragionare su OpenShift Logging 6](#2-come-ragionare-su-openshift-logging-6)
3. [Architettura logica](#3-architettura-logica)
4. [Operatori coinvolti e ordine corretto di installazione](#4-operatori-coinvolti-e-ordine-corretto-di-installazione)
5. [Le CRD e le risorse che contano davvero](#5-le-crd-e-le-risorse-che-contano-davvero)
6. [ClusterLogForwarder: anatomia completa](#6-clusterlogforwarder-anatomia-completa)
7. [LokiStack: anatomia completa](#7-lokistack-anatomia-completa)
8. [UIPlugin: come esporre i log nella console](#8-uiplugin-come-esporre-i-log-nella-console)
9. [LogFileMetricExporter: a cosa serve e quando va creato](#9-logfilemetricexporter-a-cosa-serve-e-quando-va-creato)
10. [AlertingRule e RecordingRule su Loki](#10-alertingrule-e-recordingrule-su-loki)
11. [Strategia corretta per ridurre il volume dei log](#11-strategia-corretta-per-ridurre-il-volume-dei-log)
12. [Esempio completo: CLF con drop di namespace rumorosi e debug/trace](#12-esempio-completo-clf-con-drop-di-namespace-rumorosi-e-debugtrace)
13. [Esempio completo: tuning LokiStack per errori 429](#13-esempio-completo-tuning-lokistack-per-errori-429)
14. [Esempio completo: filtro audit mirato](#14-esempio-completo-filtro-audit-mirato)
15. [Installazione e bootstrap minimo end-to-end](#15-installazione-e-bootstrap-minimo-end-to-end)
16. [Comandi di verifica e troubleshooting](#16-comandi-di-verifica-e-troubleshooting)
17. [Errori concettuali più comuni](#17-errori-concettuali-più-comuni)
18. [Best practice operative](#18-best-practice-operative)
19. [Appendice: YAML pronti all’uso](#19-appendice-yaml-pronti-alluso)
20. [Riferimenti ufficiali Red Hat](#20-riferimenti-ufficiali-red-hat)

---

## 1. Obiettivo del corso

OpenShift Logging 6.x non va pensato come “un unico prodotto con una sola CR”, ma come un insieme di componenti separati, ciascuno con una responsabilità precisa:

- **raccolta** dei log dal cluster;
- **normalizzazione** ed eventualmente filtraggio/trasformazione;
- **instradamento** dei log verso una o più destinazioni;
- **storage** dei log nel log store;
- **visualizzazione** e query via console OpenShift;
- **metriche e regole** collegate ai log.

La chiave per amministrarlo bene è separare mentalmente tre piani:

1. **collector plane** → raccoglie e inoltra i log;
2. **storage plane** → conserva e serve i log;
3. **access/UI plane** → permette di consultarli e governarne l’accesso.

In OpenShift Logging 6.x questa separazione è molto più chiara rispetto al passato.

---

## 2. Come ragionare su OpenShift Logging 6

### 2.1 Il cambio di paradigma rispetto a Logging 5.x

In Logging 6, la configurazione di raccolta e forwarding non sta più nel vecchio modello `ClusterLogging` come centro della configurazione funzionale: la documentazione ufficiale chiarisce che la configurazione di raccolta/instradamento passa alla nuova API `observability.openshift.io`, con `ClusterLogForwarder` come risorsa principale.

Questo significa, in pratica:

- il **collector** si governa dal `ClusterLogForwarder`;
- il **log store Loki** si governa dal `LokiStack`;
- la **UI** si governa dal `UIPlugin`;
- eventuali **metriche da file di log** si governano col `LogFileMetricExporter`;
- le **regole di alerting/recording** legate a Loki hanno CR dedicate.

### 2.2 Il collector supportato è uno solo

Logging 6 documenta esplicitamente che **Vector è l’unico collector supportato**. Questo è importante perché molti esempi “vecchi” presenti online si riferiscono a Fluentd, ma per l’operatività attuale la base di verità va ricondotta a Vector.

### 2.3 Loki in OpenShift Logging non è pensato come storico infinito

La documentazione RH sottolinea che la configurazione Loki fornita da OpenShift Logging è un log store **short-term**, pensato soprattutto per troubleshooting rapido e query su log recenti. Tradotto in termini architetturali: Loki va dimensionato e usato in modo realistico; se il tuo obiettivo è conservazione lunghissima, compliance o analytics storico massivo, devi ragionare con retention, object storage, policy di lifecycle e, in alcuni casi, forwarding verso sistemi esterni.

---

## 3. Architettura logica

### 3.1 Disegnino mentale

```text
[Pod / Node / API / auditd / OVN]
              |
              v
        [Collector: Vector]
              |
      +-------+--------+
      | filters/transforms |
      +-------+--------+
              |
        [Pipelines CLF]
              |
   +----------+-----------+
   |                      |
   v                      v
[LokiStack]         [Output esterni]
   |
   v
[Query / Observe / UIPlugin / LogQL]
```

### 3.2 I tre tipi logici di log

OpenShift Logging ragiona nativamente con tre categorie:

- **application**
- **infrastructure**
- **audit**

È fondamentale ricordare questo perché:

- i permessi di raccolta cambiano;
- le pipeline possono gestirli separatamente;
- la retention può essere diversa;
- l’accesso ai log può essere differenziato per tenant;
- spesso il tuning corretto richiede di separare i tre flussi.

### 3.3 Regola d’oro sulle pipeline

Se un tipo di log **non ha una pipeline che lo prende in carico**, quel tipo di log viene di fatto **scartato**. Questo è utilissimo quando vuoi ridurre volume e costo: il modo più drastico per non mandare un flusso da nessuna parte è semplicemente non definirgli una pipeline.

---

## 4. Operatori coinvolti e ordine corretto di installazione

Per avere uno stack coerente servono almeno:

- **Loki Operator** → gestisce il log store `LokiStack`;
- **Red Hat OpenShift Logging Operator** → gestisce raccolta e forwarding;
- **Cluster Observability Operator (COO)** → abilita la UI di osservabilità/logs.

### 4.1 Ordine corretto

La documentazione è chiara su due punti:

1. **Loki Operator va configurato prima** del Logging Operator;
2. **Loki Operator e Logging Operator devono avere la stessa major/minor version**.

### 4.2 Namespace tipici

- `openshift-operators-redhat` → tipicamente per il Loki Operator;
- `openshift-logging` → tipicamente per Logging Operator, `ClusterLogForwarder`, `LokiStack`, service account del collector e risorse correlate.

### 4.3 Perché l’ordine conta davvero

Perché il collector deve avere un log store coerente verso cui spedire i dati. Se prima definisci la raccolta ma non esiste ancora un Loki funzionante, la configurazione è incompleta e finirai a inseguire errori che in realtà sono sintomi di bootstrap incompleto.

---

## 5. Le CRD e le risorse che contano davvero

Queste sono le risorse da conoscere bene.

### 5.1 `ClusterLogForwarder` (`observability.openshift.io/v1`)

È il **cervello della raccolta e del forwarding**. Qui definisci:

- service account del collector;
- scheduling/tolerations/resources del collector;
- inputs;
- filters;
- outputs;
- pipelines;
- network policy del collector;
- management state.

### 5.2 `LokiStack` (`loki.grafana.com/v1`)

È il **log store**. Qui definisci:

- size;
- storage e secret dell’object store;
- schema storage;
- tenancy mode;
- retention;
- limiti di ingestione;
- network policies;
- pod placement / template / hash ring.

### 5.3 `UIPlugin` (`observability.openshift.io/v1alpha1`)

Abilita la sezione log nella console OpenShift Observe e punta a uno specifico `LokiStack`.

### 5.4 `LogFileMetricExporter` (`logging.openshift.io/v1alpha1`)

Genera metriche a partire dai file di log prodotti dai container. Non è più deployato di default col collector: va creato esplicitamente se ti servono le metriche correlate, ad esempio nel campo **Produced Logs** della console.

### 5.5 `AlertingRule` e `RecordingRule` (`loki.grafana.com/v1`)

Permettono di definire regole LogQL per alerting e recording nel contesto Loki.

### 5.6 RBAC e ServiceAccount

Non sono CRD di Logging, ma fanno parte della soluzione:

- `ServiceAccount` del collector;
- `RoleBinding` / `ClusterRoleBinding` per lettura/scrittura dei log;
- ruoli viewer per l’accesso ai tenant application/infrastructure/audit.

---

## 6. ClusterLogForwarder: anatomia completa

Il `ClusterLogForwarder` è la risorsa che un admin deve saper leggere “a colpo d’occhio”.

### 6.1 Schema concettuale

```text
spec:
  managementState
  serviceAccount
  collector
  inputs
  filters
  outputs
  pipelines
```

### 6.2 `spec.managementState`

Valori principali:

- `Managed`
- `Unmanaged`

Logica:

- con `Managed`, l’Operator riconcilia e mantiene la configurazione;
- con `Unmanaged`, smette di intervenire e tu ti assumi il governo manuale dei componenti.

**Best practice**: quasi sempre `Managed`.

### 6.3 `spec.serviceAccount`

Definisce con quale service account gira il collector.

Esempio:

```yaml
serviceAccount:
  name: logging-collector
```

Dietro questa riga c’è il tema più importante: **i permessi**. Il collector può leggere solo ciò per cui ha i ruoli appropriati.

### 6.4 RBAC minimo tipico per il collector

```bash
oc create sa logging-collector -n openshift-logging

oc adm policy add-cluster-role-to-user logging-collector-logs-writer \
  -z logging-collector -n openshift-logging

oc adm policy add-cluster-role-to-user collect-application-logs \
  -z logging-collector -n openshift-logging

oc adm policy add-cluster-role-to-user collect-infrastructure-logs \
  -z logging-collector -n openshift-logging

oc adm policy add-cluster-role-to-user collect-audit-logs \
  -z logging-collector -n openshift-logging
```

Nota importante: **audit** non viene raccolto automaticamente solo perché esiste l’input; servono anche i permessi adeguati.

### 6.5 `spec.collector`

Questa sezione governa il comportamento operativo dei pod del collector.

Campi più importanti:

- `resources`
- `nodeSelector`
- `tolerations`
- `networkPolicy`

#### Esempio

```yaml
collector:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 2Gi
  tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/infra
  networkPolicy:
    ruleSet: RestrictIngressEgress
```

#### Logica dietro questi campi

- **resources**: servono a evitare throttling, OOM e backlog del collector;
- **nodeSelector/tolerations**: servono a decidere dove far girare Vector;
- **networkPolicy**: serve quando il cluster ha policy restrittive. Se non la definisci, l’Operator non crea automaticamente una `NetworkPolicy` per il collector.

Valori documentati per `collector.networkPolicy.ruleSet`:

- `RestrictIngressEgress`
- `AllowAllIngressEgress`

### 6.6 `spec.inputs`

Gli input definiscono **quali log vengono selezionati all’ingresso**.

Puoi usare:

- input predefiniti: `application`, `infrastructure`, `audit`;
- input custom, per esempio application namespace-scoped o receiver (`http`, `syslog`).

#### Esempio application custom con include/exclude

```yaml
inputs:
  - name: app-selected
    type: application
    application:
      includes:
        - namespace: "mio-namespace-*"
      excludes:
        - namespace: "mio-namespace-test"
        - container: "sidecar-noisy*"
```

#### Logica

- usa `includes` quando vuoi stringere il perimetro all’origine;
- usa `excludes` quando vuoi togliere eccezioni rumorose;
- **`excludes` ha precedenza su `includes`**.

Questo è spesso il modo migliore per ridurre volume senza toccare il contenuto del messaggio.

### 6.7 `spec.filters`

I filtri sono trasformazioni o policy applicate alle pipeline.

Tipi importanti:

- `drop`
- `detectMultilineException`
- `kubeAPIAudit`
- altri filtri/trasformazioni a seconda del caso documentato

#### Concetto essenziale

I filtri **non lavorano da soli**: vanno sempre agganciati a una pipeline con `filterRefs`.

### 6.8 `drop` filter

È il filtro giusto quando vuoi **eliminare log non desiderati**.

Semantica ufficiale molto importante:

- un **test** passa se **tutte** le condizioni del test sono vere;
- se un test passa, il record viene droppato;
- se ci sono più test, il record viene droppato se **uno qualunque** dei test passa;
- se manca un campo, quella condizione vale `false`.

Questa logica è utilissima per filtri come `.level=debug|trace`, perché non rischi di buttare log solo perché il campo non esiste.

#### Esempio semplice

```yaml
filters:
  - name: drop-debug-trace
    type: drop
    drop:
      - test:
          - field: .level
            matches: "(?i)^debug$"
      - test:
          - field: .level
            matches: "(?i)^trace$"
```

### 6.9 `detectMultilineException`

Serve a ricomporre stack trace o eccezioni multilinea in un **singolo evento logico**.

È utilissimo con Java, ma non solo.

#### Esempio

```yaml
filters:
  - name: detect-multiline
    type: detectMultilineException
```

### 6.10 `kubeAPIAudit`

Serve a ridurre o modulare il rumore degli audit log Kubernetes/OpenShift.

Puoi definire:

- `omitStages`
- `rules`
- livelli come `None`, `Metadata`, `RequestResponse`

#### Logica

Questo filtro non serve a “fare query meglio”, ma a **decidere quanta informazione vuoi conservare del traffico audit**. È una leva molto potente sia sul volume sia sulla sensibilità del dato raccolto.

### 6.11 `spec.outputs`

Gli output definiscono **dove** mandare i log.

Tipi comuni:

- `lokiStack`
- `http`
- `syslog`
- `kafka`
- altri output supportati in base alla versione/documentazione

Per il tuo caso, il più importante è `lokiStack`.

#### Esempio `lokiStack`

```yaml
outputs:
  - name: default-lokistack
    type: lokiStack
    lokiStack:
      authentication:
        token:
          from: serviceAccount
      target:
        name: logging-loki
        namespace: openshift-logging
    tls:
      ca:
        configMapName: openshift-service-ca.crt
        key: service-ca.crt
```

#### Logica

- `target.name` e `target.namespace` devono puntare al `LokiStack` giusto;
- l’autenticazione via token di service account è il pattern più comune in-cluster;
- la sezione `tls` serve per la trust chain del servizio ricevente.

### 6.12 `spec.pipelines`

Le pipeline sono il cuore del routing.

Una pipeline collega:

- **inputRefs**
- **filterRefs** (opzionali ma potentissimi)
- **outputRefs**

#### Esempio

```yaml
pipelines:
  - name: to-default-loki
    inputRefs:
      - application
      - infrastructure
    filterRefs:
      - detect-multiline
      - drop-debug-trace
    outputRefs:
      - default-lokistack
```

#### Logica fondamentale

L’ordine dei filtri conta. Se un filtro iniziale droppa un record, quel record **non arriva** ai filtri successivi né all’output.

---

## 7. LokiStack: anatomia completa

Il `LokiStack` è la risorsa che governa storage, query, tenancy e limiti.

### 7.1 Schema concettuale

```text
spec:
  managementState
  size
  replicationFactor
  storage
  storageClassName
  tenants
  limits
  template
  networkPolicies
  hashRing
```

### 7.2 `metadata.name`

Nella pratica OpenShift Logging il nome tipico è:

```yaml
metadata:
  name: logging-loki
  namespace: openshift-logging
```

Molti esempi ufficiali usano proprio questo nome.

### 7.3 `spec.size`

Definisce il sizing Loki. Esempi tipici documentati includono taglie come `1x.extra-small`, `1x.small`, ecc.

Logica:

- non è solo “quanti log posso tenere”, ma un preset di capacità/risorse del cluster Loki;
- per produzione, la scelta del size deve essere allineata al volume reale e all’oggettistica sottostante.

### 7.4 `spec.storage`

È la sezione cruciale per il log store.

#### Esempio

```yaml
storage:
  schemas:
    - effectiveDate: "2024-10-01"
      version: v13
  secret:
    name: logging-loki-s3
    type: s3
storageClassName: gp3-csi
```

#### Logica

- `schemas` definisce schema e data di efficacia;
- `secret` contiene credenziali/config dell’object storage;
- `storageClassName` riguarda lo storage temporaneo locale necessario ai componenti Loki.

### 7.5 `spec.tenants.mode`

Per OpenShift Logging il valore tipico è:

```yaml
tenants:
  mode: openshift-logging
```

Questo abilita la modalità multi-tenant orientata ai tre flussi logici `application`, `infrastructure`, `audit`, con controllo accessi coerente.

### 7.6 Accesso ai log e ruoli viewer

L’Operator non concede a tutti l’accesso ai log di default. La documentazione indica ruoli predefiniti:

- `cluster-logging-application-view`
- `cluster-logging-infrastructure-view`
- `cluster-logging-audit-view`

Puoi usarli con `RoleBinding` o `ClusterRoleBinding` in base al perimetro desiderato.

### 7.7 `adminGroups`

In modalità `openshift-logging`, puoi definire gruppi admin custom nel `LokiStack`.

#### Esempio

```yaml
tenants:
  mode: openshift-logging
  openshift:
    adminGroups:
      - cluster-admin
      - custom-admin-group
```

Serve quando vuoi accesso amministrativo ai log per gruppi specifici, senza distribuire ruoli ad-hoc in modo manuale ovunque.

### 7.8 `spec.limits.retention`

La retention in LokiStack è una leva molto utile, ma va capita bene.

#### Due concetti fondamentali

1. puoi definire retention **globale**;
2. puoi definire retention **per tenant** e anche **per stream**, usando selector LogQL.

#### Esempio globale

```yaml
limits:
  global:
    retention:
      days: 20
      streams:
        - days: 4
          priority: 1
          selector: '{kubernetes_namespace_name=~"test.+"}'
        - days: 1
          priority: 1
          selector: '{log_type="infrastructure"}'
```

#### Attenzione

La documentazione precisa che questa retention **non impatta la retention dell’object storage**. Quindi devi coordinare:

- retention interna Loki;
- lifecycle policy dell’object storage.

### 7.9 `spec.limits.global.ingestion`

Questa sezione è centrale quando compaiono errori `429 Too Many Requests` lato Loki.

#### Esempio

```yaml
limits:
  global:
    ingestion:
      ingestionBurstSize: 16
      ingestionRate: 8
```

#### Logica precisa

- `ingestionBurstSize`: hard limit per replica distributor, in MB, della massima dimensione di campione rate-limited accettata in un singolo push;
- `ingestionRate`: soft limit sul volume ingerito per secondo.

In pratica:

- se il push singolo è più grande del burst, viene rifiutato;
- se il flusso medio supera il rate, iniziano i problemi di throttling/429.

### 7.10 `spec.networkPolicies`

Per LokiStack puoi definire una policy set, ad esempio:

```yaml
networkPolicies:
  ruleSet: RestrictIngressEgress
```

Valori documentati:

- `None`
- `RestrictIngressEgress`

### 7.11 `spec.template`

Serve per personalizzare scheduling/placement dei vari componenti Loki.

È utile, per esempio, quando vuoi mettere i componenti Loki su nodi infra dedicati con `nodeSelector` e `tolerations`.

### 7.12 `spec.hashRing`

Può servire in ambienti dove il memberlist di Loki fallisce usando solo range IP privati. La documentazione mostra il caso in cui conviene usare `instanceAddrType: podIP`.

---

## 8. UIPlugin: come esporre i log nella console

La UI dei log nella sezione **Observe** passa tramite `UIPlugin`.

### 8.1 Esempio base

```yaml
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: logging
spec:
  type: Logging
  logging:
    lokiStack:
      name: logging-loki
      logsLimit: 50
    timeout: 30s
    schema: viaq
```

### 8.2 Campi importanti

- `metadata.name`: tipicamente `logging`;
- `spec.type`: deve essere `Logging`;
- `logging.lokiStack.name`: deve puntare al tuo LokiStack;
- `logsLimit`: quante righe vuoi mostrare di default;
- `timeout`: timeout query UI;
- `schema`: può essere `otel`, `viaq`, o `select`.

### 8.3 Logica dietro `schema`

- `viaq`: ottimo se lavori col modello classico OpenShift logging;
- `otel`: utile quando stai spingendo verso il data model OpenTelemetry;
- `select`: lascia scegliere in UI.

---

## 9. LogFileMetricExporter: a cosa serve e quando va creato

Il `LogFileMetricExporter` non è più deployato di default. Se vuoi metriche derivate dai log prodotti dai container, lo devi creare tu.

### 9.1 Quando ti serve

- vuoi vedere il campo **Produced Logs** nella dashboard;
- vuoi metriche di volume prodotte dai file di log;
- vuoi una base più concreta per capacity planning del logging.

### 9.2 Esempio base

```yaml
apiVersion: logging.openshift.io/v1alpha1
kind: LogFileMetricExporter
metadata:
  name: instance
  namespace: openshift-logging
spec:
  nodeSelector: {}
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 200m
      memory: 128Mi
  tolerations: []
```

### 9.3 Network policy del metric exporter

Se il cluster usa policy restrittive, puoi definire anche qui `spec.networkPolicy.ruleSet` con valori documentati come:

- `AllowAllIngressEgress`
- `AllowIngressMetrics`

---

## 10. AlertingRule e RecordingRule su Loki

Queste risorse servono per trasformare query LogQL in oggetti operativi.

### 10.1 `AlertingRule`

Usala quando vuoi scatenare un alert a partire dai log.

#### Casi d’uso

- numero di errori oltre soglia;
- pattern ricorrenti nei log applicativi;
- eventi di sicurezza;
- errori infrastrutturali ripetuti.

#### Nota importante

La documentazione delimita anche i namespace validi a seconda del tenant (`application`, `infrastructure`, `audit`). Quindi non basta scrivere una buona query: devi anche creare la risorsa nel namespace coerente.

### 10.2 `RecordingRule`

Usala quando vuoi registrare il risultato di una query come serie riutilizzabile.

#### Casi d’uso

- aggregazioni costose riusate spesso;
- semplificazione delle dashboard;
- basi per alert più leggibili.

---

## 11. Strategia corretta per ridurre il volume dei log

Questa è la parte più utile in pratica.

### 11.1 Regola aurea

Per ridurre volume e pressione su Loki, l’ordine corretto è:

1. **non raccogliere ciò che non serve**;
2. **droppare il rumore noto**;
3. **ridurre il dettaglio degli audit log**;
4. **accorciare la retention** dove opportuno;
5. **solo alla fine** ritoccare `ingestionRate`/`ingestionBurstSize` su Loki.

### 11.2 Cosa NON fare come prima mossa

Non partire subito con tuning “cieco” di rate limit nel collector. Se hai ancora:

- namespace ultra-rumorosi;
- log `debug/trace` inutili;
- audit troppo dettagliato;

stai solo spostando il problema più a valle.

### 11.3 Prima leva: escludere namespace rumorosi

È quasi sempre la leva con miglior rapporto efficacia/rischio.

Esempi tipici:

- agenti di sicurezza;
- monitoraggi molto verbosi;
- storage operators molto chatty;
- namespace di test/lab.

### 11.4 Seconda leva: drop di `debug` e `trace`

È efficace **solo** se i log sono strutturati e hanno davvero un campo coerente, ad esempio:

- `.level`
- `.severity`
- `.log.level`

Se il log è puro testo senza struttura, il filtro non farà match. Questo non è un problema: semplicemente non riduce quel flusso.

### 11.5 Terza leva: audit filter

Gli audit log possono crescere tantissimo.

Le tecniche più utili sono:

- `omitStages: ["RequestReceived"]`
- `level: Metadata` dove non ti serve body request/response
- `level: None` per risorse notoriamente rumorose e poco rilevanti

### 11.6 Quarta leva: retention

Domanda tipica da farsi:

- tutti i log devono stare 20 giorni?
- i log application di ambienti test devono stare 4 ore, 1 giorno o 3 giorni?
- i log infrastructure davvero devono avere la stessa retention degli audit?

### 11.7 Quinta leva: tuning `LokiStack`

Quando compaiono `429`, la documentazione RH indica chiaramente che i campi da ritoccare sono `ingestionBurstSize` e `ingestionRate` nel `LokiStack`.

#### Interpretazione pratica

- aumenti `ingestionBurstSize` se singoli push sono troppo grossi;
- aumenti `ingestionRate` se il flusso medio supera il limite soft;
- ma prima devi assicurarti che non stai ingestendo spazzatura evitabile.

---

## 12. Esempio completo: CLF con drop di namespace rumorosi e debug/trace

Questa è la configurazione più vicina al tuo caso pratico.

### 12.1 Obiettivo

- mantenere collector gestito;
- spedire tutto a `logging-loki`;
- ricomporre eccezioni multilinea;
- droppare `debug/trace` dove esiste `.level`;
- droppare namespace rumorosi `openshift-storage`, `sentinelone`, `zabbix`.

### 12.2 CR completa

```yaml
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: collector
  namespace: openshift-logging
spec:
  managementState: Managed

  serviceAccount:
    name: logging-collector

  collector:
    tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/infra
      - effect: NoSchedule
        key: node.ocs.openshift.io/storage
        value: "true"

  filters:
    - name: detect-multiline
      type: detectMultilineException

    - name: drop-debug-trace
      type: drop
      drop:
        - test:
            - field: .level
              matches: "(?i)^debug$"
        - test:
            - field: .level
              matches: "(?i)^trace$"

    - name: drop-noisy-namespaces
      type: drop
      drop:
        - test:
            - field: .kubernetes.namespace_name
              matches: "^(openshift-storage|sentinelone|zabbix)$"

  outputs:
    - name: default-lokistack
      type: lokiStack
      lokiStack:
        authentication:
          token:
            from: serviceAccount
        target:
          name: logging-loki
          namespace: openshift-logging
      tls:
        ca:
          configMapName: openshift-service-ca.crt
          key: service-ca.crt

  pipelines:
    - name: enable-default-log-store
      inputRefs:
        - application
        - infrastructure
        - audit
      filterRefs:
        - detect-multiline
        - drop-debug-trace
        - drop-noisy-namespaces
      outputRefs:
        - default-lokistack
```

### 12.3 Logica dietro questa CR

- il collector resta gestito dall’Operator;
- il service account è esplicito;
- i toleration mantengono il pattern di scheduling desiderato;
- `detect-multiline` migliora la leggibilità dei log applicativi con stack trace;
- `drop-debug-trace` taglia il rumore dove il livello è strutturato;
- `drop-noisy-namespaces` elimina interi namespace rumorosi prima che arrivino a Loki;
- una singola pipeline prende tutti i tre tipi di log e li manda al LokiStack.

### 12.4 Variante più raffinata

Se vuoi essere più preciso, puoi separare le pipeline per `application`, `infrastructure` e `audit`, così applichi filtri diversi ai tre flussi.

---

## 13. Esempio completo: tuning LokiStack per errori 429

Questa CR mostra **solo** la parte rilevante per il tuning di ingestione.

```yaml
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  managementState: Managed
  size: 1x.small
  storage:
    schemas:
      - effectiveDate: "2024-10-01"
        version: v13
    secret:
      name: logging-loki-s3
      type: s3
  storageClassName: gp3-csi
  tenants:
    mode: openshift-logging
  limits:
    global:
      ingestion:
        ingestionBurstSize: 16
        ingestionRate: 8
```

### 13.1 Come interpretare i numeri

Questi valori sono **esempio di partenza**, non valori universali.

Ragionamento operativo:

- se hai push singoli troppo grossi → alza prima `ingestionBurstSize`;
- se hai flusso medio costantemente oltre soglia → alza `ingestionRate`;
- se continui ad avere 429 ma stai ancora ingestendo log inutili → correggi prima il `ClusterLogForwarder`.

### 13.2 Cosa osservare quando hai 429

Controlla:

- log del collector Vector;
- log degli ingester Loki;
- burst di volume in finestre brevi;
- eventuali namespace/tenant che dominano il traffico;
- pattern di backlog o retry.

---

## 14. Esempio completo: filtro audit mirato

Se vuoi ridurre il peso degli audit log, una CR in questo stile è spesso molto utile.

```yaml
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: collector
  namespace: openshift-logging
spec:
  managementState: Managed
  serviceAccount:
    name: logging-collector

  filters:
    - name: reduce-audit-noise
      type: kubeAPIAudit
      kubeAPIAudit:
        omitStages:
          - "RequestReceived"
        rules:
          - level: Metadata
            resources:
              - group: ""
                resources: ["pods/log", "pods/status"]
          - level: None
            resources:
              - group: ""
                resources: ["configmaps"]
                resourceNames: ["controller-leader"]
          - level: RequestResponse
            resources:
              - group: ""
                resources: ["pods"]

  outputs:
    - name: default-lokistack
      type: lokiStack
      lokiStack:
        authentication:
          token:
            from: serviceAccount
        target:
          name: logging-loki
          namespace: openshift-logging
      tls:
        ca:
          configMapName: openshift-service-ca.crt
          key: service-ca.crt

  pipelines:
    - name: audit-to-loki
      inputRefs:
        - audit
      filterRefs:
        - reduce-audit-noise
      outputRefs:
        - default-lokistack
```

### 14.1 Quando usarlo

- audit ingest troppo voluminoso;
- necessità di ridurre dettaglio body request/response;
- casi in cui alcuni oggetti Kubernetes generano moltissimo rumore ma scarso valore operativo.

---

## 15. Installazione e bootstrap minimo end-to-end

Questa sezione ti dà una checklist ragionata.

### 15.1 Prerequisiti

- cluster admin;
- object storage supportato per Loki;
- namespace `openshift-logging` pronto;
- installazione degli operatori corretta.

### 15.2 Sequenza consigliata

1. installa **Loki Operator**;
2. installa **Red Hat OpenShift Logging Operator**;
3. installa **Cluster Observability Operator** se vuoi la UI Observe;
4. crea il secret dell’object storage per Loki;
5. crea il `LokiStack`;
6. crea il service account del collector;
7. assegna i ruoli al collector;
8. crea il `UIPlugin`;
9. crea il `ClusterLogForwarder`;
10. opzionalmente crea il `LogFileMetricExporter`.

### 15.3 Esempio minimale di `LokiStack`

```yaml
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  managementState: Managed
  size: 1x.extra-small
  storage:
    schemas:
      - effectiveDate: "2024-10-01"
        version: v13
    secret:
      name: logging-loki-s3
      type: s3
  storageClassName: gp3-csi
  tenants:
    mode: openshift-logging
```

### 15.4 Esempio minimale di `UIPlugin`

```yaml
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: logging
spec:
  type: Logging
  logging:
    lokiStack:
      name: logging-loki
    logsLimit: 50
    timeout: 30s
    schema: viaq
```

### 15.5 Esempio minimale di `ClusterLogForwarder`

```yaml
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: collector
  namespace: openshift-logging
spec:
  managementState: Managed
  serviceAccount:
    name: logging-collector
  outputs:
    - name: default-lokistack
      type: lokiStack
      lokiStack:
        authentication:
          token:
            from: serviceAccount
        target:
          name: logging-loki
          namespace: openshift-logging
      tls:
        ca:
          configMapName: openshift-service-ca.crt
          key: service-ca.crt
  pipelines:
    - name: all-to-loki
      inputRefs:
        - application
        - infrastructure
      outputRefs:
        - default-lokistack
```

Se vuoi anche gli audit, devi:

- dare il ruolo `collect-audit-logs` al service account;
- aggiungere `audit` in `inputRefs`.

---

## 16. Comandi di verifica e troubleshooting

### 16.1 Verifica operatori e CRD

```bash
oc get csv -A | egrep 'logging|loki|observability'
oc api-resources | egrep 'ClusterLogForwarder|LokiStack|UIPlugin|LogFileMetricExporter|AlertingRule|RecordingRule'
```

### 16.2 Verifica `LokiStack`

```bash
oc get lokistack -n openshift-logging
oc describe lokistack logging-loki -n openshift-logging
oc get pods -n openshift-logging | egrep 'loki|gateway|ingester|distributor|querier|query-frontend|compactor|index-gateway|ruler'
```

### 16.3 Verifica `ClusterLogForwarder`

```bash
oc get clusterlogforwarder -n openshift-logging
oc get clusterlogforwarder collector -n openshift-logging -o yaml
```

### 16.4 Verifica pod collector

```bash
oc get pods -n openshift-logging -l component=collector
oc logs -n openshift-logging -l component=collector --since=30m
```

### 16.5 Cerca errori 429 / retry / TLS

```bash
oc logs -n openshift-logging -l component=collector --since=30m | egrep -i '429|too many requests|retry|tls|error|warn'
oc logs -n openshift-logging -l app.kubernetes.io/component=ingester --since=30m | egrep -i '429|rate limit|error|warn'
```

### 16.6 Verifica UI plugin

```bash
oc get uiplugin logging -A -o yaml
```

### 16.7 Verifica metric exporter

```bash
oc get logfilemetricexporter -n openshift-logging
oc get pods -n openshift-logging -l app.kubernetes.io/component=logfilesmetricexporter
```

---

## 17. Errori concettuali più comuni

### 17.1 “Aggiungo rate limit nel collector e risolvo tutto”

No. Se stai ingerendo rumore inutile, stai solo mettendo un cerotto in un punto sbagliato.

### 17.2 “Il filtro drop su `.level` mi dropperà anche i log senza campo level”

No. La documentazione chiarisce che, se il campo non esiste, la condizione fallisce e vale `false`.

### 17.3 “Se definisco output ma non pipeline, il log arriva lo stesso”

No. L’output senza pipeline non viene usato.

### 17.4 “Se metto retention in LokiStack ho sistemato anche l’object storage”

No. La retention interna Loki non sostituisce la policy di lifecycle dell’object storage.

### 17.5 “Se la UI non mostra dati, Loki è rotto”

Non necessariamente. Potresti avere:

- `UIPlugin` mancante o mal configurato;
- problemi di RBAC viewer;
- schema UI non coerente;
- query timeouts;
- `LogFileMetricExporter` assente per alcune dashboard.

---

## 18. Best practice operative

### 18.1 Separa i flussi per categoria

In produzione conviene spesso avere pipeline separate:

- `application`
- `infrastructure`
- `audit`

perché ti permettono di applicare filtri e policy diverse.

### 18.2 Togli rumore il prima possibile

Le esclusioni su input e i filtri drop precoci sono quasi sempre meglio del tuning del backend.

### 18.3 Mantieni YAML leggibili

Suggerimento pratico:

- nomi parlanti per `filters`, `outputs`, `pipelines`;
- una logica per blocchi;
- commenti solo dove servono davvero.

### 18.4 Verifica sempre con diff prima/dopo

Dopo ogni tuning chiediti:

- sono calati i volumi?
- sono spariti i 429?
- ho perso log importanti?
- ho ridotto solo il rumore o anche segnali utili?

### 18.5 Tieni distinti tre problemi diversi

1. **volume ingestito**
2. **capacità di Loki**
3. **retention/storage**

Sono correlati, ma non sono la stessa cosa.

---

## 19. Appendice: YAML pronti all’uso

### 19.1 Service account e permessi collector

```bash
oc create sa logging-collector -n openshift-logging

oc adm policy add-cluster-role-to-user logging-collector-logs-writer \
  -z logging-collector -n openshift-logging

oc adm policy add-cluster-role-to-user collect-application-logs \
  -z logging-collector -n openshift-logging

oc adm policy add-cluster-role-to-user collect-infrastructure-logs \
  -z logging-collector -n openshift-logging

oc adm policy add-cluster-role-to-user collect-audit-logs \
  -z logging-collector -n openshift-logging
```

### 19.2 `LokiStack` base

```yaml
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  managementState: Managed
  size: 1x.extra-small
  storage:
    schemas:
      - effectiveDate: "2024-10-01"
        version: v13
    secret:
      name: logging-loki-s3
      type: s3
  storageClassName: gp3-csi
  tenants:
    mode: openshift-logging
```

### 19.3 `UIPlugin` base

```yaml
apiVersion: observability.openshift.io/v1alpha1
kind: UIPlugin
metadata:
  name: logging
spec:
  type: Logging
  logging:
    lokiStack:
      name: logging-loki
    logsLimit: 50
    timeout: 30s
    schema: viaq
```

### 19.4 `LogFileMetricExporter` base

```yaml
apiVersion: logging.openshift.io/v1alpha1
kind: LogFileMetricExporter
metadata:
  name: instance
  namespace: openshift-logging
spec:
  nodeSelector: {}
  resources:
    limits:
      cpu: 500m
      memory: 256Mi
    requests:
      cpu: 200m
      memory: 128Mi
  tolerations: []
```

### 19.5 `ClusterLogForwarder` minimale verso Loki

```yaml
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: collector
  namespace: openshift-logging
spec:
  managementState: Managed
  serviceAccount:
    name: logging-collector
  outputs:
    - name: default-lokistack
      type: lokiStack
      lokiStack:
        authentication:
          token:
            from: serviceAccount
        target:
          name: logging-loki
          namespace: openshift-logging
      tls:
        ca:
          configMapName: openshift-service-ca.crt
          key: service-ca.crt
  pipelines:
    - name: app-infra-to-loki
      inputRefs:
        - application
        - infrastructure
      outputRefs:
        - default-lokistack
```

### 19.6 `ClusterLogForwarder` tuned per rumore e debug/trace

```yaml
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: collector
  namespace: openshift-logging
spec:
  managementState: Managed

  serviceAccount:
    name: logging-collector

  collector:
    tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/infra
      - effect: NoSchedule
        key: node.ocs.openshift.io/storage
        value: "true"

  filters:
    - name: detect-multiline
      type: detectMultilineException

    - name: drop-debug-trace
      type: drop
      drop:
        - test:
            - field: .level
              matches: "(?i)^debug$"
        - test:
            - field: .level
              matches: "(?i)^trace$"

    - name: drop-noisy-namespaces
      type: drop
      drop:
        - test:
            - field: .kubernetes.namespace_name
              matches: "^(openshift-storage|sentinelone|zabbix)$"

  outputs:
    - name: default-lokistack
      type: lokiStack
      lokiStack:
        authentication:
          token:
            from: serviceAccount
        target:
          name: logging-loki
          namespace: openshift-logging
      tls:
        ca:
          configMapName: openshift-service-ca.crt
          key: service-ca.crt

  pipelines:
    - name: enable-default-log-store
      inputRefs:
        - application
        - infrastructure
        - audit
      filterRefs:
        - detect-multiline
        - drop-debug-trace
        - drop-noisy-namespaces
      outputRefs:
        - default-lokistack
```

### 19.7 `LokiStack` con retention e tuning ingestione

```yaml
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: logging-loki
  namespace: openshift-logging
spec:
  managementState: Managed
  size: 1x.small
  storage:
    schemas:
      - effectiveDate: "2024-10-01"
        version: v13
    secret:
      name: logging-loki-s3
      type: s3
  storageClassName: gp3-csi
  tenants:
    mode: openshift-logging
  limits:
    global:
      ingestion:
        ingestionBurstSize: 16
        ingestionRate: 8
      retention:
        days: 20
        streams:
          - days: 4
            priority: 1
            selector: '{kubernetes_namespace_name=~"test.+"}'
          - days: 1
            priority: 1
            selector: '{log_type="infrastructure"}'
```

---

## 20. Riferimenti ufficiali Red Hat

Di seguito i riferimenti ufficiali usati come base del corso.

1. **Installing logging | Red Hat OpenShift Logging 6.4**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.4/html-single/installing_logging/index

2. **Configuring logging | Red Hat OpenShift Logging 6.4**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.4/html-single/configuring_logging/index

3. **Configuring log forwarding | Red Hat OpenShift Logging 6.4**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.4/html/configuring_logging/configuring-log-forwarding

4. **Configuring the log store | Red Hat OpenShift Logging 6.4**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.4/html/configuring_logging/configuring-lokistack-storage

5. **About OpenShift logging | Red Hat OpenShift Logging 6.4**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.4/html-single/about_openshift_logging/index

6. **Quick start | About OpenShift logging | Red Hat OpenShift Logging 6.4**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.4/html/about_openshift_logging/quick-start

7. **Upgrading logging | Red Hat OpenShift Logging 6.4**  
   https://docs.redhat.com/en/documentation/red_hat_openshift_logging/6.4/html-single/upgrading_logging/index

---

## Conclusione

Se devo riassumere il corso in una frase:

> **ClusterLogForwarder decide cosa raccogliere, filtrare e dove inviarlo; LokiStack decide come conservarlo, servirlo e limitarlo.**

Per ridurre il rumore:

1. escludi i namespace inutili;
2. droppa `debug/trace` se i log sono strutturati;
3. riduci l’audit dove ha senso;
4. abbassa la retention dove puoi;
5. solo dopo fai tuning di `ingestionBurstSize` e `ingestionRate`.

Questo è il percorso corretto, sia dal punto di vista architetturale sia dal punto di vista operativo.
