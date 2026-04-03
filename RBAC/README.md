# Cheat sheet RBAC OpenShift / Kubernetes

## Obiettivo
Raccolta pratica di comandi per verificare:
- permessi effettivi di utenti e gruppi
- Role / ClusterRole
- RoleBinding / ClusterRoleBinding
- accesso a log, exec, secrets, configmap, pvc, deployment
- troubleshooting rapido di problemi RBAC in OpenShift

> Nota: in OpenShift `oc` usa la stessa logica RBAC di Kubernetes. Molti comandi funzionano uguali anche con `kubectl`.

---

## 1. Verifiche rapide: chi sono e che contesto sto usando

```bash
oc whoami
oc whoami --show-server
oc config current-context
oc project
```

Verifica token / login corrente:

```bash
oc status
```

---

## 2. Test diretto dei permessi con `oc auth can-i`

### Sintassi base

```bash
oc auth can-i <verb> <resource>
oc auth can-i <verb> <resource> -n <namespace>
```

### Esempi base

```bash
oc auth can-i get pods -n my-namespace
oc auth can-i list pods -n my-namespace
oc auth can-i create deployments -n my-namespace
oc auth can-i delete pvc -n my-namespace
oc auth can-i get secrets -n my-namespace
oc auth can-i update configmaps -n my-namespace
```

### Verifica come altro utente (`--as`)

```bash
oc auth can-i get pods -n my-namespace --as=username
oc auth can-i create deployments -n my-namespace --as=username
```

### Verifica simulando anche il gruppo (`--as-group`)

```bash
oc auth can-i get pods -n my-namespace \
  --as=username \
  --as-group="CN=MY_GROUP,CN=Users,DC=example,DC=it"
```

### Verifica sottorisorse

```bash
oc auth can-i get pods/log -n my-namespace --as=username
oc auth can-i create pods/exec -n my-namespace --as=username
oc auth can-i create pods/portforward -n my-namespace --as=username
oc auth can-i get deployments/scale -n my-namespace --as=username
```

Forma equivalente con `--subresource`:

```bash
oc auth can-i get pods --subresource=log -n my-namespace --as=username
oc auth can-i create pods --subresource=exec -n my-namespace --as=username
oc auth can-i create pods --subresource=portforward -n my-namespace --as=username
```

### Elencare tutto ciò che puoi fare nel namespace corrente

```bash
oc auth can-i --list -n my-namespace
```

### Elencare tutto ciò che può fare un altro utente

```bash
oc auth can-i --list -n my-namespace --as=username
```

---

## 3. Comandi utili per i casi più frequenti

### Log applicativi

```bash
oc auth can-i get pods/log -n my-namespace --as=username
```

### Exec dentro i pod

```bash
oc auth can-i create pods/exec -n my-namespace --as=username
```

### Port-forward

```bash
oc auth can-i create pods/portforward -n my-namespace --as=username
```

### Lettura secrets

```bash
oc auth can-i get secrets -n my-namespace --as=username
oc auth can-i list secrets -n my-namespace --as=username
```

### Lettura configmap

```bash
oc auth can-i get configmaps -n my-namespace --as=username
```

### Scale deployment / deploymentconfig

```bash
oc auth can-i update deployments/scale -n my-namespace --as=username
oc auth can-i update deploymentconfigs/scale -n my-namespace --as=username
```

### Creazione pod

```bash
oc auth can-i create pods -n my-namespace --as=username
```

### Accesso PVC / PV

```bash
oc auth can-i get pvc -n my-namespace --as=username
oc auth can-i list pvc -n my-namespace --as=username
oc auth can-i get pv --as=username
```

### Jobs / CronJobs

```bash
oc auth can-i create jobs -n my-namespace --as=username
oc auth can-i get cronjobs -n my-namespace --as=username
```

### Route / Service / Ingress

```bash
oc auth can-i get routes.route.openshift.io -n my-namespace --as=username
oc auth can-i get services -n my-namespace --as=username
oc auth can-i get ingress -n my-namespace --as=username
```

### OpenShift Build / Image / DeploymentConfig

```bash
oc auth can-i get buildconfigs.build.openshift.io -n my-namespace --as=username
oc auth can-i get builds.build.openshift.io -n my-namespace --as=username
oc auth can-i get deploymentconfigs.apps.openshift.io -n my-namespace --as=username
oc auth can-i get imagestreams.image.openshift.io -n my-namespace --as=username
```

---

## 4. Verificare quali risorse esistono davvero nel cluster

Utile quando non sei sicuro del nome esatto di una risorsa o del relativo API group.

```bash
oc api-resources
oc api-resources | grep -i role
oc api-resources | grep -i binding
oc api-resources | grep -i route
oc api-resources | grep -i build
oc api-resources | grep -i image
oc api-resources | grep -i operator
```

Con API group:

```bash
oc api-resources -o wide | less
```

---

## 5. Vedere ruoli e binding presenti

### Role e ClusterRole

```bash
oc get role -n my-namespace
oc get clusterrole
```

Dettaglio:

```bash
oc describe role <role-name> -n my-namespace
oc describe clusterrole <clusterrole-name>
```

In YAML:

```bash
oc get role <role-name> -n my-namespace -o yaml
oc get clusterrole <clusterrole-name> -o yaml
```

### RoleBinding e ClusterRoleBinding

```bash
oc get rolebinding -n my-namespace
oc get clusterrolebinding
```

Dettaglio:

```bash
oc describe rolebinding <rb-name> -n my-namespace
oc describe clusterrolebinding <crb-name>
```

In YAML:

```bash
oc get rolebinding <rb-name> -n my-namespace -o yaml
oc get clusterrolebinding <crb-name> -o yaml
```

---

## 6. Cercare un utente o gruppo nei binding

### Nel namespace

```bash
oc get rolebinding -n my-namespace -o yaml | grep -n -B3 -A8 'username'
oc get rolebinding -n my-namespace -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
```

### A livello cluster

```bash
oc get clusterrolebinding -o yaml | grep -n -B3 -A8 'username'
oc get clusterrolebinding -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
```

### Cercare in tutti i namespace

```bash
oc get rolebinding -A -o yaml | grep -n -B3 -A8 'username'
oc get rolebinding -A -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
```

Più leggibile:

```bash
oc get rolebinding -A
oc get clusterrolebinding
```

---

## 7. Capire da quale ruolo arriva il permesso

### Metodo 1: dal binding al ruolo

1. individua il binding che contiene utente o gruppo
2. guarda `roleRef.name`
3. descrivi quel ruolo

Esempio:

```bash
oc describe rolebinding <binding-name> -n my-namespace
oc describe clusterrole view
```

### Metodo 2: grep sullo YAML

```bash
oc get rolebinding -n my-namespace -o yaml | sed -n '/CN=MY_GROUP/,+15p'
```

---

## 8. `oc adm policy who-can`: chi può fare cosa

### Verifica generale

```bash
oc adm policy who-can get pods -n my-namespace
oc adm policy who-can create deployments -n my-namespace
oc adm policy who-can get secrets -n my-namespace
oc adm policy who-can update deployments/scale -n my-namespace
oc adm policy who-can create pods/exec -n my-namespace
```

### Filtrare un gruppo

```bash
oc adm policy who-can get pods -n my-namespace | grep -i 'MY_GROUP'
oc adm policy who-can get secrets -n my-namespace | grep -i 'MY_GROUP'
```

> Nota: `who-can` non sempre gestisce bene tutte le sottorisorse. Se hai dubbi, usa `oc auth can-i` impersonando utente e gruppo: è il test più affidabile.

---

## 9. Comandi tipici di audit namespace

### Vedere i binding nel namespace

```bash
oc get rolebinding -n my-namespace
```

### Vedere i subject dei binding

```bash
oc get rolebinding -n my-namespace -o custom-columns=NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name
```

### Vedere solo i gruppi bindati

```bash
oc get rolebinding -n my-namespace -o jsonpath='{range .items[*]}{.metadata.name}{";"}{.roleRef.name}{";"}{range .subjects[*]}{.kind}{":"}{.name}{" "}{end}{"\n"}{end}'
```

### Vedere se c'è `view`, `edit`, `admin`

```bash
oc get rolebinding -n my-namespace | egrep 'view|edit|admin'
```

---

## 10. Ruoli built-in più comuni in OpenShift

### `view`
Permette in generale sola lettura delle risorse del progetto, compresi normalmente i log dei pod.

### `edit`
Permette modifica delle risorse applicative del namespace.

### `admin`
Gestione quasi completa del namespace, inclusi molti aspetti RBAC locali.

### `cluster-admin`
Permessi totali sul cluster.

Per vedere le regole esatte:

```bash
oc describe clusterrole view
oc describe clusterrole edit
oc describe clusterrole admin
oc describe clusterrole cluster-admin
```

---

## 11. Verifica utente + gruppo LDAP in modo realistico

Quando l'accesso dipende da gruppi esterni, usa sempre sia `--as` sia `--as-group`.

Esempio:

```bash
oc auth can-i get pods/log -n qw-forbearance-be \
  --as=J18148 \
  --as-group="CN=GU_OCP_QW_USER,CN=Users,DC=cariprpcpar,DC=it"
```

Se serve simulare anche il gruppo base autenticato:

```bash
oc auth can-i get pods/log -n qw-forbearance-be \
  --as=J18148 \
  --as-group="system:authenticated" \
  --as-group="CN=GU_OCP_QW_USER,CN=Users,DC=cariprpcpar,DC=it"
```

---

## 12. Troubleshooting rapido quando `can-i` dice NO

### Controlli da fare

1. namespace corretto?
2. risorsa corretta?
3. API group corretto?
4. serve una subresource (`pods/log`, `pods/exec`, `deployments/scale`)?
5. il gruppo LDAP corretto è davvero presente nel token / nella sync?
6. il permesso arriva da RoleBinding namespace o da ClusterRoleBinding?
7. stai impersonando anche `system:authenticated` quando necessario?

### Comandi utili

```bash
oc api-resources | grep -i <nome-risorsa>
oc get rolebinding -A -o yaml | grep -n -B3 -A8 'username'
oc get clusterrolebinding -o yaml | grep -n -B3 -A8 'username'
oc describe clusterrole <role-name>
```

---

## 13. Vedere gruppi, utenti e subject presenti in binding

### Solo nel namespace

```bash
oc get rolebinding -n my-namespace -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .subjects[*]}{"  - "}{.kind}{": "}{.name}{"\n"}{end}{end}'
```

### A livello cluster

```bash
oc get clusterrolebinding -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .subjects[*]}{"  - "}{.kind}{": "}{.name}{"\n"}{end}{end}'
```

---

## 14. Audit completo di un namespace

### Ruoli locali

```bash
oc get role -n my-namespace
oc get role -n my-namespace -o yaml
```

### Binding locali

```bash
oc get rolebinding -n my-namespace
oc get rolebinding -n my-namespace -o yaml
```

### ServiceAccount

```bash
oc get sa -n my-namespace
oc describe sa <sa-name> -n my-namespace
```

### Permessi tipici applicativi

```bash
oc auth can-i get pods -n my-namespace --as=username
oc auth can-i get pods/log -n my-namespace --as=username
oc auth can-i create pods/exec -n my-namespace --as=username
oc auth can-i get secrets -n my-namespace --as=username
oc auth can-i update deployments -n my-namespace --as=username
oc auth can-i update deployments/scale -n my-namespace --as=username
oc auth can-i create routes.route.openshift.io -n my-namespace --as=username
```

---

## 15. Audit completo cluster-wide

### Tutti i ClusterRole

```bash
oc get clusterrole
```

### Tutti i ClusterRoleBinding

```bash
oc get clusterrolebinding
```

### Tutti i RoleBinding su tutti i namespace

```bash
oc get rolebinding -A
```

### Tutti i binding che coinvolgono un gruppo

```bash
oc get rolebinding -A -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
oc get clusterrolebinding -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
```

---

## 16. Comandi utili OpenShift-specifici

### Chi può usare SCC

```bash
oc adm policy who-can use scc anyuid
oc adm policy who-can use scc privileged
```

### Vedere SCC assegnate a pod/serviceaccount

```bash
oc get scc
oc describe scc anyuid
oc describe scc privileged
```

### Chi può creare project

```bash
oc adm policy who-can create projectrequests
```

---

## 17. Query comode con `jsonpath` e `custom-columns`

### Binding con ruolo referenziato

```bash
oc get rolebinding -n my-namespace -o custom-columns=NAME:.metadata.name,ROLEKIND:.roleRef.kind,ROLE:.roleRef.name
```

### ClusterRoleBinding con soggetti

```bash
oc get clusterrolebinding -o custom-columns=NAME:.metadata.name,ROLE:.roleRef.name,SUBJECTS:.subjects[*].name
```

### RoleBinding con subject type + name

```bash
oc get rolebinding -n my-namespace -o jsonpath='{range .items[*]}{.metadata.name}{"; role="}{.roleRef.name}{"; subjects="}{range .subjects[*]}{.kind}{":"}{.name}{" "}{end}{"\n"}{end}'
```

---

## 18. Differenza pratica fra `RoleBinding` e `ClusterRoleBinding`

### RoleBinding
- vale dentro un namespace
- può referenziare un `Role` o un `ClusterRole`

### ClusterRoleBinding
- vale a livello cluster
- referenzia un `ClusterRole`

Esempio classico:
- `RoleBinding` nel namespace `app1` che assegna `view` al gruppo LDAP
- quel gruppo avrà `view` solo in `app1`

---

## 19. Comandi rapidi che conviene ricordare

### Capire se un utente vede i log

```bash
oc auth can-i get pods/log -n my-namespace --as=username --as-group="CN=MY_GROUP,..."
```

### Capire se un utente può fare exec

```bash
oc auth can-i create pods/exec -n my-namespace --as=username --as-group="CN=MY_GROUP,..."
```

### Trovare il gruppo nei binding

```bash
oc get rolebinding -A -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
oc get clusterrolebinding -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
```

### Capire da dove arriva il permesso

```bash
oc describe rolebinding <binding> -n my-namespace
oc describe clusterrole <role-name>
```

### Vedere tutto quello che può fare un utente

```bash
oc auth can-i --list -n my-namespace --as=username
```

---

## 20. Mini playbook pratico: “un gruppo LDAP può vedere i log in Loki/OpenShift?”

1. Verifica accesso ai log dei pod:

```bash
oc auth can-i get pods/log -n my-namespace \
  --as=username \
  --as-group="CN=MY_GROUP,CN=Users,DC=example,DC=it"
```

2. Cerca il gruppo nei binding:

```bash
oc get rolebinding -n my-namespace -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
oc get clusterrolebinding -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
```

3. Identifica il ruolo assegnato:

```bash
oc describe rolebinding <binding-name> -n my-namespace
```

4. Descrivi il ruolo:

```bash
oc describe clusterrole view
```

5. Se `can-i get pods/log` risponde `yes`, allora l'utente/gruppo può consultare i log applicativi del namespace anche tramite console / integrazione logging, salvo personalizzazioni molto particolari.

---

## 21. Comandi di raccolta completa per ticket / audit

```bash
oc whoami
oc whoami --show-server
oc project
oc get rolebinding -n my-namespace
oc get rolebinding -n my-namespace -o yaml
oc get clusterrolebinding -o yaml | grep -n -B3 -A8 'username'
oc get clusterrolebinding -o yaml | grep -n -B3 -A8 'CN=MY_GROUP'
oc auth can-i --list -n my-namespace --as=username
oc auth can-i get pods/log -n my-namespace --as=username --as-group="CN=MY_GROUP,..."
oc auth can-i create pods/exec -n my-namespace --as=username --as-group="CN=MY_GROUP,..."
oc describe clusterrole view
oc describe clusterrole edit
oc describe clusterrole admin
```

---

## 22. Note finali

- `oc auth can-i` è il test più affidabile per sapere se una specifica azione è permessa.
- `oc adm policy who-can` è ottimo per audit veloci, ma con alcune sottorisorse può non essere sempre il più comodo.
- Quando il permesso dipende da LDAP/AD, impersona sempre sia utente sia gruppo.
- Se non conosci il nome esatto della risorsa, parti sempre da `oc api-resources`.
- In OpenShift molti permessi applicativi comuni arrivano da `view`, `edit`, `admin` o da ruoli custom bindati ai gruppi.
