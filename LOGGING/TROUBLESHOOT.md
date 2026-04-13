# OpenShift Logging – Query e tuning LokiStack

---

## 1. Concetto chiave: pre-filtro vs post-filtro

Nel collector OpenShift Logging il flusso log è, semplificando:

```text
source -> filter -> sink -> Loki
```

Quindi:

- le metriche del componente `kubernetes_logs` descrivono **cosa il collector legge** dai log dei container;
- le metriche del sink `output_default_lokistack_*` descrivono **cosa arriva davvero al sink Loki dopo i filtri**;
- i log visibili in **Observe -> Logs** sono la prova finale di ciò che è stato **davvero scritto in Loki**.

### Esempio pratico
Se hai un filtro CLF che droppa `sentinelone`:

- `sentinelone` può ancora comparire nelle metriche **pre-filtro**;
- `sentinelone` **non deve più comparire** in **Observe -> Logs** negli ultimi minuti;
- il sink post-filtro non ti dirà i top namespace, ma il **totale** inoltrato.

---

## 2. Query Prometheus utili

## 2.1 Top producer pre-filtro (chi produce log sul nodo)

### Query
```promql
topk(
  10,
  sum by (pod_namespace, pod_name, container_name) (
    increase(
      vector_component_received_event_bytes_total{
        component_type="kubernetes_logs"
      }[5m]
    )
  ) / 1024 / 1024
)
```

### A cosa serve
Mostra i container che hanno generato più log **letti dal collector** negli ultimi 5 minuti.

### Come interpretarla
- È una vista **pre-filtro**.
- Serve per capire **chi è rumoroso**.
- Qui puoi ancora vedere namespace che poi vengono droppati dal CLF.

### Quando usarla
- per scegliere i namespace da filtrare;
- per vedere chi produce più volume lato nodo;
- per confrontare prima/dopo un change di workload.

---

## 2.2 Totale post-filtro verso Loki per pipeline

### Query
```promql
sum by (component_id) (
  rate(
    vector_component_received_event_bytes_total{
      component_id=~"output_default_lokistack_(application|infrastructure|audit)"
    }[5m]
  )
) / 1024 / 1024
```

### A cosa serve
Mostra il **rate reale verso Loki** per pipeline:

- `output_default_lokistack_application`
- `output_default_lokistack_infrastructure`
- `output_default_lokistack_audit`

### Come interpretarla
- Il valore è in **MiB/s** circa.
- È una vista **post-filtro**.
- Se il CLF ha ridotto bene il rumore, qui dovresti vedere valori più bassi.

### Quando usarla
- per stimare il carico vero su Loki;
- per capire quale pipeline pesa di più;
- per ragionare sul tuning di `ingestionRate`.

---

## 2.3 Totale post-filtro inviato al sink negli ultimi 5 minuti

### Query
```promql
sum by (component_id) (
  increase(
    vector_component_received_event_bytes_total{
      component_id=~"output_default_lokistack_(application|infrastructure|audit)"
    }[5m]
  )
) / 1024 / 1024
```

### A cosa serve
Mostra quanti **MiB totali** sono stati mandati al sink Loki negli ultimi 5 minuti.

### Come interpretarla
- È un **totale**, non un rate.
- Utile per confrontare finestre brevi prima/dopo una modifica.

---

## 2.4 Picco breve osservato verso il sink (stima burst)

### Query
```promql
max_over_time(
  (
    sum by (component_id) (
      increase(
        vector_component_received_event_bytes_total{
          component_id=~"output_default_lokistack_(application|infrastructure|audit)"
        }[10s]
      )
    ) / 1024 / 1024
  )[6h:10s]
)
```

### A cosa serve
Serve a stimare il **picco breve** osservato verso i sink nelle ultime 6 ore.

### Come interpretarla bene
- Il numero è in **MiB per 10 secondi**, non MiB/s.
- È una **stima operativa del burst**, non il push size perfetto.
- È utile per farsi un'idea di `ingestionBurstSize`.

### Quando usarla
- se hai `429` intermittenti;
- se vuoi capire se il problema è da burst breve o da rate medio.

---

## 2.5 429 ricevuti dal collector per pipeline

### Query
```promql
sum by (component_id) (
  increase(
    vector_http_client_responses_total{
      component_id=~"output_default_lokistack_(application|infrastructure|audit)",
      status="429"
    }[15m]
  )
)
```

### A cosa serve
Conta quante risposte HTTP `429 Too Many Requests` riceve il collector da Loki.

### Come interpretarla
- se compare solo `application`, il problema è concentrato lì;
- se compare `audit`, devi controllare sia volume sia qualità dei log audit;
- se tende a zero dopo i filtri, il change sta funzionando.

---

## 2.6 Byte scartati da Loki, raggruppati per reason

### Query
```promql
sum by (reason) (
  increase(loki_discarded_bytes_total[15m])
)
```

### A cosa serve
È una delle query più importanti. Dice **perché Loki sta scartando dati**.

### Reason tipici
- `rate_limited` -> Loki sta limitando il traffico
- `greater_than_max_sample_age` -> i log arrivano troppo vecchi
- `line_too_long` -> record troppo lungo
- `per_stream_rate_limit` -> singolo stream troppo caldo

### Come usarla
- se domina `rate_limited`, puoi valutare il tuning di `ingestionRate` / `ingestionBurstSize`;
- se domina `greater_than_max_sample_age`, il problema è più probabilmente backlog / ritardo / clock skew;
- se domina `line_too_long`, il problema è il contenuto del log, non il rate.

---

## 2.7 Sample scartati da Loki, raggruppati per reason

### Query
```promql
sum by (reason) (
  increase(loki_discarded_samples_total[15m])
)
```

### A cosa serve
Stesso concetto della query precedente, ma conta i **sample** invece dei byte.

### Quando usarla
- per confermare se il problema è numericamente esteso;
- per affiancarla a `loki_discarded_bytes_total`.

---

## 2.8 Buffer lato collector

### Query
```promql
max by (component_id) (
  vector_buffer_size_bytes{
    component_id=~"output_default_lokistack_(application|infrastructure|audit)"
  }
)
```

### A cosa serve
Mostra se il collector sta accumulando **buffer/coda** su un sink.

### Come interpretarla
- se cresce e resta alto, il collector fatica a svuotare il sink;
- se resta basso o rientra, il sistema sta recuperando.

---

## 3. Verifica pratica del filtro CLF

## 3.1 Prova finale in Observe -> Logs
Per verificare se il filtro namespace sta davvero funzionando:

1. vai in **Observe -> Logs**;
2. imposta **Last 5 minutes**;
3. filtra `namespace = sentinelone` oppure `openshift-storage`;
4. se vedi **No datapoints found**, significa che quel namespace **non sta più entrando in Loki**.

### Nota importante
Questa è la verifica più affidabile.
Le metriche del collector possono ancora mostrare log letti **prima del filtro**.

---

## 4. Comandi CLI per verificare 400 / 429 sui collector

## 4.1 Elenco pod collector
```bash
oc get pods -n openshift-logging -l app.kubernetes.io/component=collector
```

## 4.2 Cerca 429 / retry / rate limit nei collector
```bash
for p in $(oc get pods -n openshift-logging -l app.kubernetes.io/component=collector -o name); do
  echo "===== $p ====="
  oc logs -n openshift-logging "$p" --since=30m --all-containers=true | egrep -i '429|Too Many Requests|rate limit|retry'
done
```

### A cosa serve
Ti fa vedere se il collector sta ricevendo `429` da Loki e sta ritentando.

### Come leggere l'output
- `429 Too Many Requests` -> rate limit Loki
- `Retrying after error` -> Vector sta ritentando
- molti `429` concentrati su `output_default_lokistack_application` -> problema pipeline application

---

## 4.3 Cerca 400 / sample troppo vecchi / validation error
```bash
for p in $(oc get pods -n openshift-logging -l app.kubernetes.io/component=collector -o name); do
  echo "===== $p ====="
  oc logs -n openshift-logging "$p" --since=2h --all-containers=true | egrep -i '400 Bad Request|greater_than_max_sample_age|timestamp too old|too far behind|line_too_long'
done
```

### A cosa serve
Serve a capire se il problema non è di rate, ma di **validazione** o di log troppo vecchi.

### Come leggere l'output
- `400 Bad Request` + `greater_than_max_sample_age` -> log consegnati troppo tardi / timestamp vecchi
- `line_too_long` -> record troppo lungo
- questi errori **non si risolvono** alzando solo `ingestionRate`

---

## 4.4 Cerca errori/warn generici dei collector
```bash
oc logs -n openshift-logging -l app.kubernetes.io/component=collector --since=30m --all-containers=true --prefix | egrep -i 'error|warn|drop|retry|reload|reconcil'
```

### A cosa serve
Per vedere warning e segnali generali dopo un cambio di CLF o LokiStack.

---

## 5. Come leggere i problemi più comuni

## 5.1 `rate_limited`
Significa che Loki ha limitato il traffico in ingresso.

### Cosa fare
- ridurre il volume con i filtri CLF;
- identificare quale pipeline pesa di più;
- solo se serve, rivedere `ingestionRate` / `ingestionBurstSize`.

---

## 5.2 `greater_than_max_sample_age`
Significa che Loki ha rifiutato log troppo vecchi.

### Cause tipiche
- backlog nel collector;
- log consegnati in ritardo;
- clock skew / orario non allineato;
- stream che arrivano troppo indietro nel tempo.

### Cosa fare
- controllare l'ora dei nodi e dei componenti;
- capire quale pipeline/stream ritarda;
- ridurre backlog e rumore;
- non partire subito dal tuning LokiStack.

---

## 5.3 `line_too_long`
Significa che Loki rifiuta entry troppo grandi.

### Cosa fare
- intervenire sul contenuto del log;
- ridurre audit verbosi;
- evitare payload giganteschi in singole linee.

---

## 6. Tuning LokiStack: quando ha senso

Ha senso ritoccare `LokiStack.spec.limits.global.ingestion` **solo se**:

- il `reason` dominante è davvero `rate_limited`;
- i `429` sono persistenti e non solo transitori;
- hai già ridotto il rumore lato CLF;
- il cluster ha margine di risorse.

### Non partire dal tuning se
- domina `greater_than_max_sample_age`;
- domina `line_too_long`;
- il traffico medio post-filtro è basso e i 429 sono sporadici.

---

## 7. Come leggere i valori di LokiStack

### Leggi il blocco ingestion
```bash
oc get lokistack logging-loki -n openshift-logging -o jsonpath='{.spec.limits.global.ingestion}{"\n"}'
```

### Oppure visualizza il blocco completo
```bash
oc get lokistack logging-loki -n openshift-logging -o yaml | sed -n '/limits:/,/managementState:/p'
```

---

## 8. Come scegliere valori sensati

## 8.1 `ingestionRate`
È il **soft limit** in MB/s.

### Regola pratica
1. misura il traffico reale post-filtro con la query sui sink;
2. prendi il picco sostenuto della pipeline problematica;
3. aggiungi un margine del 20-30%;
4. arrotonda per eccesso.

### Esempio
Se `application` sta spesso tra 6 e 8 MiB/s, un valore ragionevole può essere **10 o 12**.

---

## 8.2 `ingestionBurstSize`
È il **hard limit** per burst/push.

### Regola pratica
1. guarda il picco breve osservato con `increase(...[10s])`;
2. usa quel valore come minimo di riferimento;
3. aggiungi margine prudente.

### Nota importante
La query sul burst è una **stima operativa**, non il push size esatto di Loki.

---

## 9. Esempio di patch LokiStack

### Patch prudente
```bash
oc patch lokistack logging-loki -n openshift-logging --type=merge -p '
spec:
  limits:
    global:
      ingestion:
        ingestionRate: 12
        ingestionBurstSize: 24
'
```

### Quando usarla
Solo se:
- il `reason` prevalente è `rate_limited`;
- i 429 continuano dopo i filtri;
- hai verificato che il collo di bottiglia non sia `greater_than_max_sample_age`.

---

## 10. Workflow consigliato

1. **Verifica i filtri CLF** con `Observe -> Logs`.
2. **Misura il traffico post-filtro** con la query sui sink.
3. **Guarda i 429** con `vector_http_client_responses_total`.
4. **Guarda i discarded** con `loki_discarded_bytes_total` per capire il `reason`.
5. **Solo dopo** decidi se toccare `LokiStack`.

---

## 11. Checklist rapida

### Se vedi 429
- controlla quale `component_id` li riceve;
- guarda `rate_limited` nei discarded;
- misura il rate post-filtro;
- valuta tuning LokiStack.

### Se vedi 400
- cerca `greater_than_max_sample_age`;
- cerca `line_too_long`;
- verifica backlog, ritardo e clock skew;
- non alzare subito i limiti.

### Se vuoi verificare un filtro namespace
- `Observe -> Logs`
- `Last 5 minutes`
- filtro sul namespace
- `No datapoints found` = filtro efficace

---

## 12. Riferimenti

- Red Hat OpenShift Container Platform 4.16 – Troubleshooting logging
- Red Hat OpenShift Logging 6.4 – Configuring logging / Configuring log forwarding
- Grafana Loki – Request validation and rate limits
- Vector – Internal metrics / HTTP client metrics
