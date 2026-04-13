# OpenShift Service Mesh 2.x Cheatsheet

Cheatsheet pratica per OpenShift Service Mesh (OSSM 2.x) su OpenShift, orientata a:

- replica di uno `ServiceMeshControlPlane` (SMCP) su un cluster nuovo
- ingress gateway con `NodePort` fissi `30001` e `30002`
- rimozione di `nodeSelector`/`tolerations` infra
- rimozione di `additionalIngress` di backend
- disabilitazione di Jaeger nel control plane
- verifica e troubleshooting operativo

> Esempi pensati per namespace di control plane `istio-system`.

---

## 1. Prerequisiti minimi

Verifica gli operator installati:

```bash
oc get csv -A | egrep 'service-mesh|kiali|jaeger|tempo|distributed-tracing'
oc get crd | egrep 'servicemeshcontrolplanes|servicemeshmemberrolls|jaegers|tempostacks'
```

Verifica le API disponibili:

```bash
oc api-resources | egrep 'ServiceMeshControlPlane|ServiceMeshMemberRoll|Istio'
oc explain servicemeshcontrolplane --api-version=maistra.io/v2
```

Crea il namespace del control plane se manca:

```bash
oc new-project istio-system
```

---

## 2. Ispezione veloce del mesh esistente

SMCP corrente:

```bash
oc -n istio-system get smcp
oc -n istio-system get smcp basic -o yaml
oc -n istio-system get smcp basic -o yaml | kubectl-neat
```

Stato sintetico:

```bash
oc -n istio-system get smcp basic -o jsonpath='{.status.conditions[*].type}{"\n"}{.status.conditions[*].status}{"\n"}{.status.conditions[*].message}{"\n"}'
```

Gateway e service creati:

```bash
oc -n istio-system get svc
oc -n istio-system get deploy
oc -n istio-system get pods -o wide
```

Verifica porte ingress:

```bash
oc -n istio-system get svc istio-ingressgateway -o jsonpath='{range .spec.ports[*]}{.name}{" port="}{.port}{" nodePort="}{.nodePort}{" targetPort="}{.targetPort}{"\n"}{end}'
```

---

## 3. Manifest completo SMCP "target" pulito

Caratteristiche:

- `version: v2.6`
- `mode: ClusterWide`
- `policy/telemetry: Istiod`
- **Jaeger disabilitato**
- nessun `nodeSelector` infra
- nessuna `additionalIngress`
- ingress principale `NodePort`
- `30001` per HTTP
- `30002` per HTTPS
- `openshiftRoute.enabled: false`

Salva come `smcp-basic.yaml`:

```yaml
apiVersion: maistra.io/v2
kind: ServiceMeshControlPlane
metadata:
  name: basic
  namespace: istio-system
spec:
  version: v2.6

  mode: ClusterWide
  profiles:
    - default

  policy:
    type: Istiod

  telemetry:
    type: Istiod

  security:
    certificateAuthority:
      type: Istiod
      istiod:
        type: PrivateKey
        privateKey:
          rootCADir: /etc/cacerts
    dataPlane:
      mtls: true

  addons:
    grafana:
      enabled: true
      install:
        service:
          ingress:
            enabled: true
          metadata:
            annotations:
              service.alpha.openshift.io/serving-cert-secret-name: grafana-tls
    kiali:
      enabled: true
      name: kiali
      install:
        dashboard:
          viewOnly: false
        service:
          ingress:
            enabled: true
    prometheus:
      enabled: true
      install:
        service:
          ingress:
            enabled: true
          metadata:
            annotations:
              service.alpha.openshift.io/serving-cert-secret-name: prometheus-tls

  gateways:
    enabled: true
    openshiftRoute:
      enabled: false

    ingress:
      enabled: true
      runtime:
        deployment:
          autoScaling:
            enabled: false
        container:
          resources:
            requests:
              cpu: 10m
              memory: 128Mi
      service:
        type: NodePort
        ports:
          - name: status-port
            port: 15021
            protocol: TCP
            targetPort: 15021
          - name: http
            port: 80
            protocol: TCP
            targetPort: 8080
            nodePort: 30001
          - name: https
            port: 443
            protocol: TCP
            targetPort: 8443
            nodePort: 30002

    egress:
      enabled: true
      runtime:
        deployment:
          autoScaling:
            enabled: false
        container:
          resources:
            requests:
              cpu: 10m
              memory: 128Mi
      service: {}

  runtime:
    components:
      pilot:
        deployment:
          autoScaling:
            enabled: false
        container:
          resources:
            requests:
              cpu: 10m
              memory: 128Mi
    defaults:
      deployment:
        podDisruption:
          enabled: false
      container:
        resources:
          requests:
            cpu: 10m
            memory: 128Mi
```

Applica:

```bash
oc apply -f smcp-basic.yaml
```

Controlla il rollout:

```bash
oc -n istio-system get smcp basic
oc -n istio-system get pods
oc -n istio-system get deploy
oc -n istio-system get svc istio-ingressgateway
```

---

## 4. Verifica veloce dei NodePort

```bash
oc -n istio-system get svc istio-ingressgateway -o jsonpath='{range .spec.ports[*]}{.name}{" port="}{.port}{" nodePort="}{.nodePort}{"\n"}{end}'
```

Output atteso:

```text
status-port port=15021 nodePort=<assegnato dal cluster oppure vuoto se non fissato>
http port=80 nodePort=30001
https port=443 nodePort=30002
```

Verifica completa del service:

```bash
oc -n istio-system describe svc istio-ingressgateway
```

---

## 5. ServiceMeshMemberRoll minimo

Il control plane esiste, ma per fare entrare namespace applicativi nella mesh devi aggiungerli al `ServiceMeshMemberRoll`.

Salva come `smmr-default.yaml`:

```yaml
apiVersion: maistra.io/v1
kind: ServiceMeshMemberRoll
metadata:
  name: default
  namespace: istio-system
spec:
  members:
    - my-app-ns
    - my-api-ns
```

Applica:

```bash
oc apply -f smmr-default.yaml
```

Verifica:

```bash
oc -n istio-system get smmr default -o yaml
```

---

## 6. Sidecar injection

Controlla i namespace membri:

```bash
oc -n istio-system get smmr default -o jsonpath='{.spec.members[*]}'
```

Per deployment specifico, annota o etichetta il pod template.

### Annotazione sul Deployment

```bash
oc -n my-app-ns patch deploy myapp \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/metadata/annotations","value":{"sidecar.istio.io/inject":"true"}}]'
```

### Label sul Deployment

```bash
oc -n my-app-ns label deploy myapp sidecar.istio.io/inject=true --overwrite
```

Verifica che il pod abbia 2 container:

```bash
oc -n my-app-ns get pods
oc -n my-app-ns get pod <pod> -o jsonpath='{.spec.containers[*].name}{"\n"}'
```

Controlla l'injection:

```bash
oc -n my-app-ns describe pod <pod> | egrep -i 'istio-proxy|sidecar.istio.io/inject'
```

---

## 7. Gateway + VirtualService di esempio

### Gateway

```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: public-gateway
  namespace: my-app-ns
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - app.example.com
```

### VirtualService

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp-vs
  namespace: my-app-ns
spec:
  hosts:
    - app.example.com
  gateways:
    - public-gateway
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: myapp.my-app-ns.svc.cluster.local
            port:
              number: 8080
```

Applica:

```bash
oc -n my-app-ns apply -f gateway.yaml
oc -n my-app-ns apply -f virtualservice.yaml
```

Verifica:

```bash
oc -n my-app-ns get gateway,virtualservice
oc -n istio-system logs deploy/istio-ingressgateway -c istio-proxy --tail=100
```

---

## 8. Accesso tramite NodePort

Trova un node IP raggiungibile:

```bash
oc get nodes -o wide
```

Test HTTP:

```bash
curl -H 'Host: app.example.com' http://<NODE_IP>:30001/
```

Test HTTPS:

```bash
curl -k -H 'Host: app.example.com' https://<NODE_IP>:30002/
```

---

## 9. Patch utili

### Disabilitare Jaeger su uno SMCP già esistente

```bash
oc -n istio-system patch smcp basic --type=json \
  -p='[
    {"op":"remove","path":"/spec/tracing"},
    {"op":"remove","path":"/spec/addons/jaeger"}
  ]'
```

### Impostare NodePort 30001/30002 sull'ingress esistente

```bash
oc -n istio-system patch smcp basic --type=merge -p '
spec:
  gateways:
    ingress:
      service:
        type: NodePort
        ports:
          - name: status-port
            port: 15021
            protocol: TCP
            targetPort: 15021
          - name: http
            port: 80
            protocol: TCP
            targetPort: 8080
            nodePort: 30001
          - name: https
            port: 443
            protocol: TCP
            targetPort: 8443
            nodePort: 30002
'
```

### Disabilitare l'OpenShift route management

```bash
oc -n istio-system patch smcp basic --type=merge -p '
spec:
  gateways:
    openshiftRoute:
      enabled: false
'
```

---

## 10. Troubleshooting rapido

### 10.1 Errore `metadata.resourceVersion must be specified for an update`

Capita quando usi `oc replace` oppure stai cercando di aggiornare un dump completo senza `resourceVersion` valida.

Correzione pratica:

- usa un manifest pulito con solo `apiVersion`, `kind`, `metadata.name`, `metadata.namespace`, `spec`
- usa `oc apply -f ...`
- **non** includere `status`, `managedFields`, `uid`, `creationTimestamp`, `resourceVersion`

Comando corretto:

```bash
oc apply -f smcp-basic.yaml
```

---

### 10.2 Errore `Dependency "Jaeger CRD" is missing`

Succede se nello SMCP hai:

```yaml
spec:
  tracing:
    type: Jaeger
```

oppure:

```yaml
spec:
  addons:
    jaeger:
      ...
```

ma nel cluster non hai Jaeger Operator / CRD.

Correzioni possibili:

- installare Jaeger Operator
- oppure rimuovere `spec.tracing` e `spec.addons.jaeger`

Verifiche:

```bash
oc get crd | grep jaeger
oc get csv -A | grep -i jaeger
```

---

### 10.3 Il service `istio-ingressgateway` non ha i NodePort attesi

Verifica:

```bash
oc -n istio-system get svc istio-ingressgateway -o yaml
```

Possibili cause:

- SMCP non ancora reconciled
- operator che ha rifiutato il campo
- altra configurazione del gateway ancora presente

Controlla stato SMCP:

```bash
oc -n istio-system get smcp basic -o yaml | egrep -A5 'conditions:|message:|reason:'
```

Controlla eventi:

```bash
oc -n istio-system get events --sort-by=.metadata.creationTimestamp
```

---

### 10.4 I pod applicativi non ricevono il sidecar

Checklist:

```bash
oc -n istio-system get smmr default -o yaml
oc -n my-app-ns get deploy myapp -o yaml | egrep -A3 'sidecar.istio.io/inject|labels:|annotations:'
oc -n my-app-ns get pod <pod> -o jsonpath='{.spec.containers[*].name}{"\n"}'
```

Cause tipiche:

- namespace non presente nel `ServiceMeshMemberRoll`
- deployment/pod senza injection abilitata
- pod non ricreati dopo la modifica

Forza rollout:

```bash
oc -n my-app-ns rollout restart deploy/myapp
oc -n my-app-ns rollout status deploy/myapp
```

---

## 11. Comandi utili "day 2"

Pods e controllo rapido:

```bash
oc -n istio-system get pods -o wide
oc -n istio-system top pod
oc -n istio-system describe pod <pod>
```

Log ingress gateway:

```bash
oc -n istio-system logs deploy/istio-ingressgateway -c istio-proxy --tail=200
```

Log pilot:

```bash
oc -n istio-system logs deploy/istiod --tail=200
```

Lista risorse mesh namespace applicativo:

```bash
oc -n my-app-ns get gateway,virtualservice,destinationrule,peerauthentication,authorizationpolicy,requestauthentication
```

Dump completo namespace mesh:

```bash
oc -n istio-system get all,cm,secret,sa,role,rolebinding
```

---

## 12. Cleanup

Rimuovere SMCP:

```bash
oc -n istio-system delete smcp basic
```

Rimuovere SMMR:

```bash
oc -n istio-system delete smmr default
```

Rimuovere namespace di test:

```bash
oc delete project my-app-ns
```

---

## 13. Note operative

- Per **SMCP esistenti**, preferisci `oc apply` o `oc patch`; evita `oc replace` su YAML esportati al volo.
- Se non ti servono route OpenShift gestite automaticamente, tieni `spec.gateways.openshiftRoute.enabled: false`.
- Se vuoi solo accesso da F5 / VIP / nodi, i `NodePort` fissi sono spesso la soluzione più semplice.
- Se il cluster è nuovo, parti dal control plane minimale e aggiungi dopo SMMR, Gateway e VirtualService.
- Se hai installato **Tempo** ma non **Jaeger**, non lasciare `spec.tracing.type: Jaeger` nello SMCP.

---

## 14. Riferimenti ufficiali da tenere aperti

- OpenShift Container Platform 4.16 - Service Mesh
- OpenShift Container Platform 4.19 - Service Mesh 2.x
- Red Hat OpenShift Service Mesh 3 - Migrating from Service Mesh 2 to 3

