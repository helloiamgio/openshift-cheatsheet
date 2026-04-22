# Runbook — Patch di risorse Kubernetes / OpenShift

---

## 1. Concetti base

In Kubernetes/OpenShift puoi modificare una risorsa in vari modi:

```bash
oc edit <kind> <name> -n <namespace>
```

oppure con patch diretta:

```bash
oc patch <kind> <name> -n <namespace> --type <tipo_patch> -p '<payload>'
```

I tipi patch più usati sono:

| Tipo | Quando usarlo |
|---|---|
| `merge` | Il più comodo per modificare campi semplici dentro oggetti YAML/JSON |
| `json` | Utile per aggiungere/rimuovere/sostituire campi in modo preciso |
| `strategic` | Utile su alcune risorse Kubernetes native, ma non sempre supportato sulle CRD |

Su OpenShift puoi usare sia `oc` sia `kubectl`. Negli esempi uso `oc`, ma quasi tutti i comandi valgono anche con `kubectl`.

---

## 2. Prima regola: fai sempre backup della risorsa

Prima di patchare:

```bash
oc get <kind> <name> -n <namespace> -o yaml > backup-<kind>-<name>.yaml
```

Esempio:

```bash
oc get argocd openshift-gitops -n openshift-gitops -o yaml > backup-argocd-openshift-gitops.yaml
```

Se hai `kubectl-neat`:

```bash
oc get argocd openshift-gitops -n openshift-gitops -o yaml | kubectl-neat > backup-argocd-openshift-gitops-neat.yaml
```

---

## 3. Verificare il valore attuale di un campo

Con `jsonpath`:

```bash
oc get <kind> <name> -n <namespace> -o jsonpath='{.spec.campo}{"\n"}'
```

Esempio per OpenShift GitOps notifications:

```bash
oc get argocd openshift-gitops -n openshift-gitops \
  -o jsonpath='{.spec.notifications.enabled}{"\n"}'
```

Con `jq`:

```bash
oc get <kind> <name> -n <namespace> -o json | jq '.spec'
```

Esempio:

```bash
oc get argocd openshift-gitops -n openshift-gitops -o json | jq '.spec.notifications'
```

---

## 4. Patch semplice con `--type merge`

### 4.1 Impostare un campo booleano a `true`

```bash
oc patch <kind> <name> -n <namespace> \
  --type merge \
  -p '{"spec":{"campo":{"enabled":true}}}'
```

Esempio reale: abilitare notifications su OpenShift GitOps:

```bash
oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  -p '{"spec":{"notifications":{"enabled":true}}}'
```

Verifica:

```bash
oc get argocd openshift-gitops -n openshift-gitops \
  -o jsonpath='{.spec.notifications.enabled}{"\n"}'
```

### 4.2 Impostare un campo booleano a `false`

```bash
oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  -p '{"spec":{"notifications":{"enabled":false}}}'
```

### 4.3 Cambiare una stringa

```bash
oc patch <kind> <name> -n <namespace> \
  --type merge \
  -p '{"spec":{"campo":"nuovo-valore"}}'
```

Esempio:

```bash
oc patch route my-route -n my-namespace \
  --type merge \
  -p '{"spec":{"host":"app.example.com"}}'
```

### 4.4 Cambiare un numero

```bash
oc patch <kind> <name> -n <namespace> \
  --type merge \
  -p '{"spec":{"replicas":3}}'
```

Esempio Deployment:

```bash
oc patch deployment my-app -n my-namespace \
  --type merge \
  -p '{"spec":{"replicas":3}}'
```

Nota: per i replica è spesso più leggibile usare:

```bash
oc scale deployment my-app -n my-namespace --replicas=3
```

---

## 5. Patch annidata

Se il campo è dentro più livelli YAML:

```yaml
spec:
  server:
    route:
      enabled: false
```

Patch:

```bash
oc patch <kind> <name> -n <namespace> \
  --type merge \
  -p '{"spec":{"server":{"route":{"enabled":true}}}}'
```

Esempio ArgoCD route:

```bash
oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  -p '{"spec":{"server":{"route":{"enabled":true}}}}'
```

---

## 6. Patch di risorse gestite da operator/controller

Se la console mostra:

```text
Managed resource
This resource is managed by ...
```

la patch può essere sovrascritta.

Prima controlla owner, label e annotation:

```bash
oc get <kind> <name> -n <namespace> -o json | jq '.metadata.ownerReferences'
```

```bash
oc get <kind> <name> -n <namespace> -o json | jq '.metadata.labels'
```

```bash
oc get <kind> <name> -n <namespace> -o json | jq '.metadata.annotations'
```

Esempio:

```bash
oc get argocd openshift-gitops -n openshift-gitops -o json | jq '.metadata.ownerReferences'
```

```bash
oc get argocd openshift-gitops -n openshift-gitops -o json | jq '.metadata.labels, .metadata.annotations'
```

Se la risorsa è gestita da ArgoCD/GitOps, modifica il manifest nel repository Git o nella `Application` che la riconcilia.

Cerca eventuali Application ArgoCD:

```bash
oc get applications.argoproj.io -A
```

Cerca riferimenti alla risorsa:

```bash
oc get applications.argoproj.io -A -o yaml | grep -B20 -A20 "openshift-gitops"
```

---

## 7. Patch con file JSON/YAML

Se il payload è lungo, evita il one-liner e usa un file.

Crea file:

```bash
cat > patch.json <<'EOF'
{
  "spec": {
    "notifications": {
      "enabled": true
    }
  }
}
EOF
```

Applica:

```bash
oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  --patch-file patch.json
```

---

## 8. Patch label

### 8.1 Aggiungere o aggiornare una label

Modo consigliato:

```bash
oc label <kind> <name> -n <namespace> chiave=valore --overwrite
```

Esempio:

```bash
oc label namespace my-namespace environment=prod --overwrite
```

Con patch:

```bash
oc patch <kind> <name> -n <namespace> \
  --type merge \
  -p '{"metadata":{"labels":{"environment":"prod"}}}'
```

### 8.2 Rimuovere una label

```bash
oc label <kind> <name> -n <namespace> chiave-
```

Esempio:

```bash
oc label namespace my-namespace environment-
```

Con JSON patch:

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"remove","path":"/metadata/labels/environment"}]'
```

---

## 9. Patch annotation

### 9.1 Aggiungere o aggiornare una annotation

Modo consigliato:

```bash
oc annotate <kind> <name> -n <namespace> chiave=valore --overwrite
```

Esempio:

```bash
oc annotate deployment my-app -n my-namespace backup.velero.io/backup-volumes=data --overwrite
```

Con patch:

```bash
oc patch <kind> <name> -n <namespace> \
  --type merge \
  -p '{"metadata":{"annotations":{"mia.annotation/chiave":"valore"}}}'
```

### 9.2 Rimuovere una annotation

```bash
oc annotate <kind> <name> -n <namespace> chiave-
```

Esempio:

```bash
oc annotate deployment my-app -n my-namespace backup.velero.io/backup-volumes-
```

Con JSON patch, attenzione agli slash `/` nella chiave: vanno scritti come `~1`.

Esempio annotation:

```text
backup.velero.io/backup-volumes
```

Path JSON patch:

```text
/metadata/annotations/backup.velero.io~1backup-volumes
```

Comando:

```bash
oc patch deployment my-app -n my-namespace \
  --type json \
  -p='[{"op":"remove","path":"/metadata/annotations/backup.velero.io~1backup-volumes"}]'
```

---

## 10. JSON Patch: add, replace, remove

Il tipo `json` usa operazioni precise.

### 10.1 Replace

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"replace","path":"/spec/replicas","value":3}]'
```

Esempio:

```bash
oc patch deployment my-app -n my-namespace \
  --type json \
  -p='[{"op":"replace","path":"/spec/replicas","value":3}]'
```

### 10.2 Add

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"add","path":"/spec/nuovoCampo","value":"valore"}]'
```

### 10.3 Remove

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"remove","path":"/spec/campoDaRimuovere"}]'
```

Esempio:

```bash
oc patch route my-route -n my-namespace \
  --type json \
  -p='[{"op":"remove","path":"/spec/host"}]'
```

---

## 11. Patch di liste/array

### 11.1 Aggiungere un elemento in fondo a una lista

Usa `/-` per append.

Esempio: aggiungere una tolleration a un Deployment:

```bash
oc patch deployment my-app -n my-namespace \
  --type json \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/tolerations/-",
      "value": {
        "key": "node-role.kubernetes.io/infra",
        "operator": "Exists",
        "effect": "NoSchedule"
      }
    }
  ]'
```

Se la lista `tolerations` non esiste, prima devi crearla:

```bash
oc patch deployment my-app -n my-namespace \
  --type json \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/tolerations",
      "value": []
    }
  ]'
```

Poi aggiungi l'elemento.

### 11.2 Sostituire il primo elemento di una lista

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"replace","path":"/spec/lista/0","value":"nuovo-valore"}]'
```

### 11.3 Rimuovere il primo elemento di una lista

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"remove","path":"/spec/lista/0"}]'
```

---

## 12. Patch nodeSelector e tolerations su Deployment

### 12.1 Aggiungere nodeSelector

```bash
oc patch deployment my-app -n my-namespace \
  --type merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"node-role.kubernetes.io/infra":""}}}}}'
```

### 12.2 Aggiungere toleration infra

Se `tolerations` non esiste:

```bash
oc patch deployment my-app -n my-namespace \
  --type merge \
  -p '{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/infra","operator":"Exists","effect":"NoSchedule"}]}}}}'
```

Attenzione: con `merge`, una lista viene sostituita interamente. Se esistono già altre toleration, meglio usare JSON patch append.

```bash
oc patch deployment my-app -n my-namespace \
  --type json \
  -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/tolerations/-",
      "value": {
        "key": "node-role.kubernetes.io/infra",
        "operator": "Exists",
        "effect": "NoSchedule"
      }
    }
  ]'
```

---

## 13. Patch risorse CPU/Memoria su Deployment

### 13.1 Cambiare requests/limits del primo container

```bash
oc patch deployment my-app -n my-namespace \
  --type merge \
  -p '{
    "spec": {
      "template": {
        "spec": {
          "containers": [
            {
              "name": "my-container",
              "resources": {
                "requests": {
                  "cpu": "100m",
                  "memory": "256Mi"
                },
                "limits": {
                  "cpu": "500m",
                  "memory": "512Mi"
                }
              }
            }
          ]
        }
      }
    }
  }'
```

Per i Deployment, lo strategic merge può funzionare meglio sulle liste di container perché usa `name` come chiave di merge:

```bash
oc patch deployment my-app -n my-namespace \
  --type strategic \
  -p '{
    "spec": {
      "template": {
        "spec": {
          "containers": [
            {
              "name": "my-container",
              "resources": {
                "requests": {
                  "cpu": "100m",
                  "memory": "256Mi"
                },
                "limits": {
                  "cpu": "500m",
                  "memory": "512Mi"
                }
              }
            }
          ]
        }
      }
    }
  }'
```

Nota: sulle CRD lo strategic merge spesso non è supportato. Usa `merge` o `json`.

---

## 14. Patch Service

### 14.1 Cambiare type da ClusterIP a NodePort

```bash
oc patch svc my-service -n my-namespace \
  --type merge \
  -p '{"spec":{"type":"NodePort"}}'
```

### 14.2 Cambiare type da NodePort a ClusterIP

Prima potresti dover rimuovere i `nodePort` assegnati.

```bash
oc patch svc my-service -n my-namespace \
  --type merge \
  -p '{"spec":{"type":"ClusterIP"}}'
```

### 14.3 Impostare un nodePort specifico

Attenzione: il `nodePort` deve essere libero e nel range ammesso dal cluster.

```bash
oc patch svc my-service -n my-namespace \
  --type json \
  -p='[
    {
      "op": "replace",
      "path": "/spec/ports/0/nodePort",
      "value": 30080
    }
  ]'
```

---

## 15. Patch Route OpenShift

### 15.1 Cambiare host

```bash
oc patch route my-route -n my-namespace \
  --type merge \
  -p '{"spec":{"host":"my-app.apps.example.com"}}'
```

### 15.2 Cambiare termination TLS

```bash
oc patch route my-route -n my-namespace \
  --type merge \
  -p '{"spec":{"tls":{"termination":"edge","insecureEdgeTerminationPolicy":"Redirect"}}}'
```

### 15.3 Rimuovere TLS da una Route

```bash
oc patch route my-route -n my-namespace \
  --type json \
  -p='[{"op":"remove","path":"/spec/tls"}]'
```

---

## 16. Patch IngressController OpenShift

### 16.1 Cambiare numero repliche router

```bash
oc patch ingresscontroller default -n openshift-ingress-operator \
  --type merge \
  -p '{"spec":{"replicas":3}}'
```

### 16.2 Aggiungere nodePlacement su infra

```bash
oc patch ingresscontroller default -n openshift-ingress-operator \
  --type merge \
  -p '{
    "spec": {
      "nodePlacement": {
        "nodeSelector": {
          "matchLabels": {
            "node-role.kubernetes.io/infra": ""
          }
        },
        "tolerations": [
          {
            "key": "node-role.kubernetes.io/infra",
            "operator": "Exists",
            "effect": "NoSchedule"
          }
        ]
      }
    }
  }'
```

---

## 17. Patch MachineConfigPool

### 17.1 Pausare un MachineConfigPool

```bash
oc patch mcp worker \
  --type merge \
  -p '{"spec":{"paused":true}}'
```

### 17.2 Riattivare un MachineConfigPool

```bash
oc patch mcp worker \
  --type merge \
  -p '{"spec":{"paused":false}}'
```

Verifica:

```bash
oc get mcp
```

---

## 18. Patch Operator Subscription

### 18.1 Cambiare installPlanApproval a Manual

```bash
oc patch subscription <subscription-name> -n <namespace> \
  --type merge \
  -p '{"spec":{"installPlanApproval":"Manual"}}'
```

Esempio:

```bash
oc patch subscription openshift-gitops-operator -n openshift-operators \
  --type merge \
  -p '{"spec":{"installPlanApproval":"Manual"}}'
```

### 18.2 Cambiare channel

```bash
oc patch subscription <subscription-name> -n <namespace> \
  --type merge \
  -p '{"spec":{"channel":"stable"}}'
```

Esempio:

```bash
oc patch subscription openshift-gitops-operator -n openshift-operators \
  --type merge \
  -p '{"spec":{"channel":"latest"}}'
```

---

## 19. Patch ConfigMap

### 19.1 Cambiare un valore semplice

```bash
oc patch configmap my-config -n my-namespace \
  --type merge \
  -p '{"data":{"CHIAVE":"valore"}}'
```

### 19.2 Aggiungere più chiavi

```bash
oc patch configmap my-config -n my-namespace \
  --type merge \
  -p '{"data":{"KEY1":"value1","KEY2":"value2"}}'
```

### 19.3 Rimuovere una chiave

Con JSON patch:

```bash
oc patch configmap my-config -n my-namespace \
  --type json \
  -p='[{"op":"remove","path":"/data/CHIAVE"}]'
```

Se la chiave contiene `/`, sostituire `/` con `~1`.

---

## 20. Patch Secret

### 20.1 Aggiornare una chiave in un Secret

I valori nei Secret devono essere base64.

```bash
echo -n 'nuova-password' | base64 -w0
```

Su macOS:

```bash
echo -n 'nuova-password' | base64
```

Patch:

```bash
oc patch secret my-secret -n my-namespace \
  --type merge \
  -p '{"data":{"password":"bnVvdmEtcGFzc3dvcmQ="}}'
```

Metodo più sicuro per generare il payload:

```bash
PASSWORD_B64="$(echo -n 'nuova-password' | base64 -w0)"

oc patch secret my-secret -n my-namespace \
  --type merge \
  -p "{\"data\":{\"password\":\"${PASSWORD_B64}\"}}"
```

---

## 21. Patch SecurityContextConstraints

### 21.1 Aggiungere un ServiceAccount a una SCC

Modo consigliato:

```bash
oc adm policy add-scc-to-user <scc-name> -z <serviceaccount> -n <namespace>
```

Esempio:

```bash
oc adm policy add-scc-to-user privileged -z my-sa -n my-namespace
```

Patch manuale, da usare con cautela:

```bash
oc patch scc privileged \
  --type json \
  -p='[
    {
      "op": "add",
      "path": "/users/-",
      "value": "system:serviceaccount:my-namespace:my-sa"
    }
  ]'
```

---

## 22. Patch ClusterLogForwarder esempio

Esempio generico per abilitare un campo booleano dentro una CRD:

```bash
oc patch clusterlogforwarder collector -n openshift-logging \
  --type merge \
  -p '{"spec":{"collector":{"someField":true}}}'
```

Per CRD complesse, meglio prima esportare:

```bash
oc get clusterlogforwarder collector -n openshift-logging -o yaml > clf-before.yaml
```

Modificare un file locale e poi applicare:

```bash
oc apply -f clf-before.yaml
```

Oppure usare `oc edit`:

```bash
oc edit clusterlogforwarder collector -n openshift-logging
```

---

## 23. Patch ArgoCD/OpenShift GitOps

### 23.1 Abilitare notifications

```bash
oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  -p '{"spec":{"notifications":{"enabled":true}}}'
```

Verifica:

```bash
oc get argocd openshift-gitops -n openshift-gitops \
  -o jsonpath='{.spec.notifications.enabled}{"\n"}'
```

Controlla pod/deployment:

```bash
oc get deploy,pod -n openshift-gitops | egrep -i 'notification|argocd'
```

### 23.2 Disabilitare notifications

```bash
oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  -p '{"spec":{"notifications":{"enabled":false}}}'
```

### 23.3 Abilitare Grafana

```bash
oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  -p '{"spec":{"grafana":{"enabled":true}}}'
```

### 23.4 Abilitare route server

```bash
oc patch argocd openshift-gitops \
  -n openshift-gitops \
  --type merge \
  -p '{"spec":{"server":{"route":{"enabled":true}}}}'
```

---

## 24. Patch su tutte le risorse di un namespace

### 24.1 Aggiungere una label a tutti i Deployment del namespace

```bash
for d in $(oc get deploy -n my-namespace -o name); do
  oc label "$d" -n my-namespace managed-by=ops --overwrite
done
```

### 24.2 Patchare tutte le Deployment con una label

```bash
oc get deploy -n my-namespace -l app=my-app -o name | while read d; do
  oc patch "$d" -n my-namespace \
    --type merge \
    -p '{"spec":{"replicas":2}}'
done
```

### 24.3 Patchare tutti i namespace non di sistema

Esempio: aggiungere una label a namespace applicativi.

```bash
oc get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
  | grep -vE '^(openshift-|kube-)' \
  | while read ns; do
      oc label ns "$ns" checked-by=ops --overwrite
    done
```

---

## 25. Dry-run e validazione

### 25.1 Dry-run server-side

Non sempre disponibile per tutte le operazioni patch, ma utile quando supportato.

```bash
oc patch <kind> <name> -n <namespace> \
  --type merge \
  -p '{"spec":{"campo":"valore"}}' \
  --dry-run=server -o yaml
```

### 25.2 Controllare differenze prima/dopo

Prima:

```bash
oc get <kind> <name> -n <namespace> -o yaml > before.yaml
```

Patch:

```bash
oc patch <kind> <name> -n <namespace> \
  --type merge \
  -p '{"spec":{"campo":"valore"}}'
```

Dopo:

```bash
oc get <kind> <name> -n <namespace> -o yaml > after.yaml
```

Diff:

```bash
diff -u before.yaml after.yaml
```

Con `kubectl-neat`:

```bash
oc get <kind> <name> -n <namespace> -o yaml | kubectl-neat > after-neat.yaml
```

---

## 26. Rollback veloce

Se hai salvato il backup YAML:

```bash
oc apply -f backup-<kind>-<name>.yaml
```

Esempio:

```bash
oc apply -f backup-argocd-openshift-gitops.yaml
```

Attenzione: se la risorsa è gestita da un operator, il rollback manuale può essere a sua volta riconciliato dal controller.

---

## 27. Errori comuni

### 27.1 Invalid JSON

Errore tipico:

```text
invalid character ...
```

Controlla virgolette e apici.

Buona pratica:

```bash
cat <<'EOF' > patch.json
{
  "spec": {
    "notifications": {
      "enabled": true
    }
  }
}
EOF

jq . patch.json
```

Poi:

```bash
oc patch argocd openshift-gitops -n openshift-gitops \
  --type merge \
  --patch-file patch.json
```

### 27.2 Campo inesistente con JSON patch replace

`replace` richiede che il campo esista. Se non esiste, usa `add`.

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"add","path":"/spec/nuovoCampo","value":"valore"}]'
```

### 27.3 Liste sovrascritte con merge patch

Con `--type merge`, le liste vengono normalmente sostituite.

Esempio rischioso:

```bash
oc patch deployment my-app -n my-namespace \
  --type merge \
  -p '{"spec":{"template":{"spec":{"tolerations":[...]}}}}'
```

Se vuoi aggiungere un solo elemento senza perdere gli altri, usa `--type json` con path `/-`.

### 27.4 La patch funziona ma poi torna indietro

Probabile risorsa gestita da:

- Operator
- ArgoCD / OpenShift GitOps
- ACM
- Helm
- Kustomize
- altro controller

Controlla:

```bash
oc get <kind> <name> -n <namespace> -o json | jq '.metadata.ownerReferences'
```

```bash
oc get <kind> <name> -n <namespace> -o json | jq '.metadata.labels, .metadata.annotations'
```

---

## 28. Mini cheat sheet finale

### Merge patch

```bash
oc patch <kind> <name> -n <namespace> \
  --type merge \
  -p '{"spec":{"campo":"valore"}}'
```

### JSON patch replace

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"replace","path":"/spec/campo","value":"valore"}]'
```

### JSON patch add

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"add","path":"/spec/campo","value":"valore"}]'
```

### JSON patch remove

```bash
oc patch <kind> <name> -n <namespace> \
  --type json \
  -p='[{"op":"remove","path":"/spec/campo"}]'
```

### Verifica campo

```bash
oc get <kind> <name> -n <namespace> \
  -o jsonpath='{.spec.campo}{"\n"}'
```

### Backup

```bash
oc get <kind> <name> -n <namespace> -o yaml > backup.yaml
```

### Rollback

```bash
oc apply -f backup.yaml
```

---

## 29. Template rapido da riusare

```bash
KIND="argocd"
NAME="openshift-gitops"
NS="openshift-gitops"

oc get "$KIND" "$NAME" -n "$NS" -o yaml > "backup-${KIND}-${NAME}.yaml"

oc patch "$KIND" "$NAME" -n "$NS" \
  --type merge \
  -p '{"spec":{"notifications":{"enabled":true}}}'

oc get "$KIND" "$NAME" -n "$NS" \
  -o jsonpath='{.spec.notifications.enabled}{"\n"}'
```

---

## 30. Template con variabili e patch-file

```bash
KIND="argocd"
NAME="openshift-gitops"
NS="openshift-gitops"

cat > patch.json <<'EOF'
{
  "spec": {
    "notifications": {
      "enabled": true
    }
  }
}
EOF

jq . patch.json

oc get "$KIND" "$NAME" -n "$NS" -o yaml > "backup-${KIND}-${NAME}.yaml"

oc patch "$KIND" "$NAME" -n "$NS" \
  --type merge \
  --patch-file patch.json

oc get "$KIND" "$NAME" -n "$NS" -o yaml | kubectl-neat
```
