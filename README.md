# OpenShift Cheat Sheet

![Alt text](https://github.com/helloiamgio/openshift-cheatsheet/blob/main/architecture_overview.png)

https://docs.openshift.com/container-platform/4.14/cli_reference/openshift_cli/developer-cli-commands.html

## **Login and Configuration**

### oc Autocompletion
```bash
oc completion bash >>/etc/bash_completion.d/oc_completion
```

### Login with a user
```bash
oc login https://console-openshift-console.apps-crc.testing:8443 -u developer -p developer
```

### Login as system admin
```bash
oc login -u system:admin
```

### User Information
```bash
oc whoami
oc whoami --show-console
oc whoami --show-server

oc cluster-info

oc cluster-info dump
```

### View your configuration
```bash
oc config view
```

### Update the current context to have users login to the desired namespace
```bash
oc config set-context `oc config current-context` --namespace=<project_name>
```

### List OAuth Access Tokens
```bash
oc get useroauthaccesstokens
```

---

## **Useful Commands**

### List all Projects
```bash
oc get projects
```

### Switch to a Project
```bash
oc project myproject
```

### Get Resources in a Project
List all resources in the current project:
```bash
oc get all
```

List pods with custom output:
```bash
oc get pods -o wide
```

### Apply Configuration from a File
```bash
oc apply -f config.yaml
```

### Create Objects Using Bash Here Documents
Create a ConfigMap directly using a here document:
```bash
oc apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-config
  namespace: myproject
data:
  key: value
EOF
```

### Export Resources to a File
```bash
oc get deployment my-deployment -o yaml > deployment.yaml
```

### Delete a Resource
```bash
oc delete pod my-pod
```

### Debug a Pod
Start a debug session for a pod:
```bash
oc debug pod/my-pod
```

### Check Cluster Status
```bash
oc status
```

### View Cluster Nodes
```bash
oc get nodes
```

### Describe a Node
```bash
oc describe node <node-name>
```

### Get Logs for a Pod
```bash
oc logs my-pod
```

### Follow Logs for a Pod
```bash
oc logs -f my-pod
```

### Port Forward a Pod
```bash
oc port-forward my-pod 8080:80
```

### Execute a Command in a Running Pod
```bash
oc exec my-pod -- ls /tmp
```

### Scale a Deployment
```bash
oc scale deployment my-deployment --replicas=3
```

### Create a New Application
```bash
oc new-app my-image-stream
```

### Manage Kubeconfig Files
Switch kubeconfig contexts:
```bash
oc config use-context <context-name>
```

List all contexts:
```bash
oc config get-contexts
```

Set a specific context as default:
```bash
oc config set-context --current --namespace=myproject
```

Merge multiple kubeconfig files:
```bash
KUBECONFIG=config1:config2:config3 oc config view --merge --flatten > merged-config
```

### Create a new app from a GitHub Repository
```bash
oc new-app https://github.com/sclorg/cakephp-ex
```

### New app from a different branch
```bash
oc new-app --name=html-dev nginx:1.10~https://github.com/joe-speedboat/openshift.html.devops.git#mybranch
```

### Create objects from a file
```bash
oc create -f myobject.yaml -n myproject
```

### Delete objects contained in a file
```bash
oc delete -f myobject.yaml -n myproject
```

### Create or merge objects from a file
```bash
oc apply -f myobject.yaml -n myproject
```

### Update existing object
```bash
oc patch svc mysvc --type merge --patch '{"spec":{"ports":[{"port": 8080, "targetPort": 5000}]}}'
```

### Monitor Pod status
```bash
watch oc get pods
```

### Get a Specific Item (podIP) using a Go template
```bash
oc get pod example-pod-2 --template='{{.status.podIP}}'
```

### Gather information on a project's pod deployment with node information
```bash
oc get pods -o wide
```

### Hide inactive Pods
```bash
oc get pods --show-all=false
```

### Display all resources
```bash
oc get all,secret,configmap
```

### Get the OpenShift Console Address
```bash
oc get -n openshift-console route console
```

### Get the Pod name from the Selector and rsh into it
```bash
POD=$(oc get pods -l app=myapp -o name) oc rsh -n $POD
```

### Execute a single command in a running pod
```bash
oc exec $POD $COMMAND
```

### Create a pod for the container image "fedora" and execute commands with it
```bash
oc run fedora-pod --image=fedora --restart=Never --command -- sleep infinity
```

### Copy from local folder byteman-4.0.12 to Pod wildfly-basic-1-mrlt5 under the folder /opt/wildfly
```bash
oc cp ./byteman-4.0.12 wildfly-basic-1-mrlt5:/opt/wildfly
```

---

## **Deployments**

### Manual deployment
```bash
oc rollout latest ruby-ex
```

### Rollout a Deployment
```bash
oc rollout latest deployment/my-deployment
```

### Pause a Deployment
```bash
oc rollout pause deployment/my-deployment
```

### Resume a Deployment
```bash
oc rollout resume deployment/my-deployment
```

### Scale a Deployment
```bash
oc scale deployment/my-deployment --replicas=3
```

### Undo a Deployment Rollout
```bash
oc rollout undo deployment/my-deployment
```

### Check Deployment History
```bash
oc rollout history deployment/my-deployment
```

### Set Deployment Strategies
```yaml
spec:
  strategy:
    type: Rolling
    rollingParams:
      intervalSeconds: 1
      updatePeriodSeconds: 1
      timeoutSeconds: 600
      maxUnavailable: 25%
      maxSurge: 25%
```

### Define resource requests and limits in DeploymentConfig
```bash
oc set resources deployment nginx --limits=cpu=200m,memory=512Mi --requests=cpu=100m,memory=256Mi
```

### Define livenessProbe and readinessProbe in DeploymentConfig
```bash
oc set probe dc/nginx --readiness --get-url=http://:8080/healthz --initial-delay-seconds=10
oc set probe dc/nginx --liveness --get-url=http://:8080/healthz --initial-delay-seconds=10
```

### Scale the number of Pods to 2
```bash
oc scale dc/nginx --replicas=2
```

### Define Horizontal Pod Autoscaler (HPA)
```bash
oc autoscale dc foo --min=2 --max=4 --cpu-percent=10
```

---

## **ConfigMaps**

### View ConfigMap Data
```bash
oc get configmap my-config -o yaml
```

### Update a ConfigMap
```bash
oc create configmap my-config --from-literal=key=value --dry-run=client -o yaml | oc apply -f -
```

---

## **Managing Routes**

### Create a route
```bash
oc expose service ruby-ex
```

### Create Route and expose it through a custom Hostname
```bash
oc expose service ruby-ex --hostname=<custom-hostname>
```

### Read the Route Host attribute
```bash
oc get route my-route -o jsonpath --template="{.spec.host}"
```

### Forward traffic from pod "myphp" from 8080 to local 8080
```bash
oc port-forward pod/myphp 8080:8080
```

---

## **Managing Services**

### Make a service idle. When the service is next accessed it will automatically boot up the pods again
```bash
oc idle ruby-ex
```

### Read a Service IP
```bash
oc get services rook-ceph-mon-a --template='{{.spec.clusterIP}}'
```

---

## **Resource Usage**

### List the memory and CPU usage of all pods in the cluster
```bash
oc adm top pods -A --sum
```

### List the resource usage of the containers in the pod "mypod" in the "example" namespace
```bash
oc adm top pods mypod -n example --containers
```

### Resource consumption for the node
```bash
oc adm top node
```

### List all resources, their status, and their types in the "example" namespace
```bash
oc get all -n example --show-kind
```

### Displays the resource consumption for each container running on the node (requires "cri-tools")
```bash
crictl stats
```

---

## **Clean up Resources**

### Delete Completed Pods
```bash
oc delete pod --field-selector=status.phase==Succeeded --all-namespaces
oc get pods --all-namespaces |  awk '{if ($4 == "Completed") system ("oc delete pod " $2 " -n " $1 )}'

oc delete pod --field-selector=status.phase==Failed --all-namespaces
oc delete pod --field-selector=status.phase==Pending --all-namespaces
oc delete pod --field-selector=status.phase==Evicted --all-namespaces
oc get pods --all-namespaces |  awk '{if ($4 != "Running") system ("oc delete pod " $2 " -n " $1 )}'
```



### Change the image garbage collection (GC) thresholds
Modify kubelet GC settings:
```bash
oc label machineconfigpool worker custom-kubelet=enabled
cat <<EOF | oc apply -f -
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: custom-config
spec:
  machineConfigPoolSelector:
    matchLabels:
      custom-kubelet: enabled
  kubeletConfig:
    ImageGCHighThresholdPercent: 70
    ImageGCLowThresholdPercent: 60
EOF
```

### Full cleanup with Podman
Run a full system prune:
```bash
sudo podman system prune -a -f
```

### Delete all resources
```bash
oc delete all --all
```

### Delete resources for one specific app
```bash
oc delete services -l app=ruby-ex
oc delete all -l app=ruby-ex
```

### Clean up old docker images on nodes

#### Keeping up to three tag revisions and resources younger than sixty minutes
```bash
oc adm prune images --keep-tag-revisions=3 --keep-younger-than=60m
```

#### Pruning every image that exceeds defined limits
```bash
oc adm prune images --prune-over-size-limit
```

---

## **Jobs**

### Create a simple Job
```bash
kubectl create job hello --image=alpine -- echo "Hello World"
```

### Create a CronJob that prints "Hello World" every minute
```bash
kubectl create cronjob hello --image=alpine --schedule="*/1 * * * *" -- echo "Hello World"
```

---

## **Cluster**

### Set control-plane nodes as NoSchedulable
```bash
oc patch schedulers.config.openshift.io/cluster --type merge --patch '{"spec":{"mastersSchedulable": false}}'
```
This removes the worker label from the masters. OpenShift components will move to worker nodes when rescheduled. Delete the pods to trigger reconciliation.

---

### Set a Default Node Selector
```bash
oc patch namespace default -p '{"metadata": {"annotations": {"openshift.io/node-selector": "node-role.kubernetes.io/worker"}}}'
```

### Disable Project-wide Node Selector
```bash
oc annotate namespace default openshift.io/node-selector-
```

### Routers

#### Rollout the latest deployment
```bash
oc rollout -n openshift-ingress restart deployment/router-default
```

#### Delete router pods to force reconciliation
```bash
oc delete pod -n openshift-ingress -l ingresscontroller.operator.openshift.io/deployment-ingresscontroller=default
```

---


## **RBAC**

### List role per groups
```bash
oc get rolebindings,clusterrolebindings --all-namespaces -o json | jq -r '
.items[] | 
select(.subjects[]? | select(.kind == "Group")) as $binding |
$binding.subjects[] | 
select(.kind == "Group") | 
"NAMESPACE: \($binding.metadata.namespace // "Cluster-wide") KIND: \($binding.kind) NAME: \($binding.metadata.name) ROLE: \($binding.roleRef.name) GROUP: \(.name)"'
```

### Add a role to a user
```bash
oc adm policy add-role-to-user admin oia -n python
```

### Add a cluster role to a user
```bash
oc adm policy add-cluster-role-to-user cluster-reader system:serviceaccount:monitoring:default
```

### Add a security context constraint (SCC) to a user
```bash
oc adm policy add-scc-to-user anyuid -z default
```


### Show SCC and add policy
```bash
oc get pods -A -o custom-columns="NAME:.metadata.name,SCC:.metadata.annotations.openshift\.io/scc"
oc get pods -o custom-columns="NAME:.metadata.name,SECURITY_CONTEXT:.spec.securityContext"

oc get deployment <DEPLOY> -n <NAMESPACE> -o yaml | oc adm policy scc-subject-review -f -
oc get pod <POD> -o yaml | oc adm policy scc-subject-review -f -

oc adm policy add-scc-to-user hostmount-anyuid -z default

oc get scc -o custom-columns=Name:.metadata.name,Users:.users,Priority:.priority
oc get scc restricted-v2 -o custom-columns=SECCOMP_PROFILE:.seccompProfiles 
```

---

## **Identity Providers**

### Add an HTPasswd Identity Provider
Create a secret with the htpasswd file:
```bash
oc create secret generic htpass-secret --from-file=htpasswd=/path/to/htpasswd -n openshift-config
```

Patch the OAuth resource to add the htpasswd provider:
```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: my_htpasswd_provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
```
Apply the configuration:
```bash
oc apply -f oauth.yaml
```

### Add a GitHub Identity Provider
Create a GitHub OAuth client:
```bash
oc create secret generic github-secret --from-literal=clientSecret=<your-client-secret> -n openshift-config
```

Patch the OAuth resource to add the GitHub provider:
```yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: github
    mappingMethod: claim
    type: GitHub
    github:
      clientID: <your-client-id>
      clientSecret:
        name: github-secret
      organizations:
      - my-org
```
Apply the configuration:
```bash
oc apply -f oauth.yaml
```

---

## **Images**

### List All Images in the Cluster
```bash
oc get images
```

### Import an Image from an External Registry
```bash
oc import-image myimage:latest --from=docker.io/library/myimage:latest --confirm
```

### Tag an Image for Internal Use
```bash
oc tag myimage:latest myproject/myimage:stable
```

### Prune Unused Images
```bash
oc adm prune images --confirm
```

### Build an Image from Source Code
```bash
oc new-build https://github.com/openshift/ruby-hello-world.git --name=ruby-app
```

### Start a Build
```bash
oc start-build ruby-app
```

### Monitor Build Logs
```bash
oc logs -f bc/ruby-app
```

### Deploy an Image
```bash
oc new-app myimage:stable -n myproject
```

---

### Image Registry

#### Rollout the latest deployment
```bash
oc rollout -n openshift-image-registry restart deploy/image-registry
```

#### Delete image registry pods
```bash
oc delete pod -n openshift-image-registry -l docker-registry=default
```

---

### Monitoring Stack

#### Rollout the latest deployments and statefulsets
```bash
oc rollout -n openshift-monitoring restart statefulset/alertmanager-main
oc rollout -n openshift-monitoring restart statefulset/prometheus-k8s
oc rollout -n openshift-monitoring restart deployment/grafana
oc rollout -n openshift-monitoring restart deployment/kube-state-metrics
oc rollout -n openshift-monitoring restart deployment/openshift-state-metrics
oc rollout -n openshift-monitoring restart deployment/prometheus-adapter
oc rollout -n openshift-monitoring restart deployment/telemeter-client
oc rollout -n openshift-monitoring restart deployment/thanos-querier
```

#### Delete monitoring stack pods to force reconciliation
```bash
oc delete pod -n openshift-monitoring -l app=alertmanager
oc delete pod -n openshift-monitoring -l app=prometheus
oc delete pod -n openshift-monitoring -l app=grafana
oc delete pod -n openshift-monitoring -l app.kubernetes.io/name=kube-state-metrics
oc delete pod -n openshift-monitoring -l k8s-app=openshift-state-metrics
oc delete pod -n openshift-monitoring -l name=prometheus-adapter
oc delete pod -n openshift-monitoring -l k8s-app=telemeter-client
oc delete pod -n openshift-monitoring -l app.kubernetes.io/component=query-layer
```

---

### List All Container Images

#### List all container images running in a cluster
```bash
oc get pods -A -o go-template --template='{{range .items}}{{range .spec.containers}}{{printf "%s\\n" .image -}} {{end}}{{end}}' | sort -u | uniq
```

#### List all container images stored in a cluster
```bash
for node in $(oc get nodes -o name); do
  oc debug ${node} -- chroot /host sh -c 'crictl images -o json' 2>/dev/null | jq -r .images[].repoTags[];
done | sort -u
```

---

## **Cluster Version**

### Switch Cluster Version Channel
```bash
oc patch \
  --patch='{"spec": {"channel": "prerelease-4.1"}}' \
  --type=merge \
  clusterversion/version
```

---

### Unmanage Operators

#### Retrieve current overrides
```bash
oc get -o json clusterversion version | jq .spec.overrides
```

#### Add a `ComponentOverride` to set the network operator unmanaged
1. Extract the operator definition:
   ```bash
   head -n5 /tmp/mystuff/0000_07_cluster-network-operator_03_daemonset.yaml
   ```
   Example:
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: network-operator
     namespace: openshift-network-operator
   ```

2. Create the patch YAML file:
   If no overrides exist:
   ```yaml
   - op: add
     path: /spec/overrides
     value:
     - kind: Deployment
       group: apps
       name: network-operator
       namespace: openshift-network-operator
       unmanaged: true
   ```
   If overrides already exist:
   ```yaml
   - op: add
     path: /spec/overrides/-
     value:
     - kind: Deployment
       group: apps
       name: network-operator
       namespace: openshift-network-operator
       unmanaged: true
   ```

3. Apply the patch:
   ```bash
   oc patch clusterversion version --type json -p "$(cat version-patch.yaml)"
   ```

#### Verify
```bash
oc get -o json clusterversion version | jq .spec.overrides
```

---

### Disabling the Cluster Version Operator
```bash
oc scale --replicas 0 -n openshift-cluster-version deployments/cluster-version-operator
```

---

## **Machine Config**

### List all MachineConfig objects
```bash
oc get machineconfigs
```

### View details of a specific MachineConfig
```bash
oc describe machineconfig <machineconfig-name>
```

### Create a custom MachineConfig
Example YAML:
```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  name: custom-config
  labels:
    machineconfiguration.openshift.io/role: worker
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - path: /etc/mycustomconfig
        contents:
          source: data:,custom%20content%20here
```
Apply the configuration:
```bash
oc apply -f custom-config.yaml
```

### Update Kubelet Configuration
Create a KubeletConfig:
```yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: KubeletConfig
metadata:
  name: custom-kubelet
spec:
  machineConfigPoolSelector:
    matchLabels:
      custom-kubelet: enabled
  kubeletConfig:
    cpuManagerPolicy: "static"
    cpuManagerReconcilePeriod: "5s"
```
Apply the configuration:
```bash
oc apply -f kubelet-config.yaml
```

---

## **Monitoring**

### List Monitoring Stack Components
```bash
oc get pods -n openshift-monitoring
```

### Restart a Monitoring Component
```bash
oc rollout restart deployment/grafana -n openshift-monitoring
```

### Silence Alerts
Create a silence using the Alertmanager UI or CLI. Example CLI:
```bash
amtool silence add alertname="TargetDown" instance="example-instance"
```

### Query Prometheus
Access the Prometheus UI or use `oc` to query:
```bash
oc exec -n openshift-monitoring prometheus-k8s-0 -c prometheus -- curl 'http://localhost:9090/api/v1/query?query=up'
```

### Enable User Workload Monitoring
Patch the config to enable it:
```bash
oc patch configmap cluster-monitoring-config -n openshift-monitoring --patch='{"data":{"config.yaml":"enableUserWorkload: true"}}'
```

### Monitor Custom Metrics
Deploy a custom application exposing metrics and configure Prometheus to scrape them by creating a `ServiceMonitor`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: custom-app-monitor
  labels:
    team: custom-app
spec:
  selector:
    matchLabels:
      app: custom-app
  endpoints:
  - port: metrics
```
Apply the configuration:
```bash
oc apply -f custom-app-monitor.yaml
```

---

## **Operator-Lifecycle-Manager (OLM)**

### List Installed Operators
```bash
oc get csv -n openshift-operators
```

### Install an Operator
Create a subscription for the operator:
```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: my-operator
  namespace: openshift-operators
spec:
  channel: stable
  name: my-operator
  source: operatorhubio-catalog
  sourceNamespace: openshift-marketplace
```
Apply the subscription:
```bash
oc apply -f subscription.yaml
```

### Check the Status of an Operator
```bash
oc get csv -n openshift-operators
```

### Uninstall an Operator
Delete the subscription and CSV:
```bash
oc delete subscription my-operator -n openshift-operators
oc delete csv my-operator.v1.0.0 -n openshift-operators
```

### Approve a Manual InstallPlan
```bash
oc patch installplan install-xxxxx -n openshift-operators --type merge --patch '{"spec": {"approved": true}}'
```

### View Operator Logs
Find the operator's pod and view logs:
```bash
oc get pods -n openshift-operators
oc logs my-operator-pod -n openshift-operators
```

### Create a Custom Resource for an Operator
Example YAML:
```yaml
apiVersion: app.example.com/v1
kind: ExampleApp
metadata:
  name: example-app
  namespace: myproject
spec:
  size: 3
```
Apply the custom resource:
```bash
oc apply -f example-app.yaml
```

### Check Operator Conditions
```bash
oc get csv my-operator.v1.0.0 -n openshift-operators -o jsonpath='{.status.conditions}'
```

### List Available Operators in the Marketplace
```bash
oc get packagemanifests -n openshift-marketplace
```

### Describe a Specific Operator
```bash
oc describe packagemanifest my-operator -n openshift-marketplace
```

### Update an Operator Subscription
```bash
oc patch subscription my-operator -n openshift-operators --type merge --patch '{"spec": {"channel": "stable"}}'
```

---

## **Pull Secrets**

### Create a Pull Secret
Create a pull secret to authenticate with an external container registry:
```bash
oc create secret docker-registry my-pull-secret \
  --docker-server=<registry-server> \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email>
```

### Link a Pull Secret to a ServiceAccount
```bash
oc secrets link default my-pull-secret --for=pull
```

### View Linked Secrets for a ServiceAccount
```bash
oc get serviceaccount default -o yaml
```

### Update the Global Pull Secret
1. Edit the pull secret:
   ```bash
   oc edit secret pull-secret -n openshift-config
   ```
2. Add the credentials for the desired registry in the `auths` section.

### Add Credentials to a Namespaced Secret
Create a new secret with updated credentials:
```bash
oc create secret docker-registry my-namespace-pull-secret \
  --docker-server=<registry-server> \
  --docker-username=<username> \
  --docker-password=<password> \
  --docker-email=<email> -n mynamespace
```
Link the new secret to a service account:
```bash
oc secrets link my-serviceaccount my-namespace-pull-secret --for=pull -n mynamespace
```

---

## **Registries**

### List Images in the Internal Registry
```bash
oc get is -A
```

### Expose the Internal Registry Externally
```bash
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type merge \
  --patch '{"spec":{"defaultRoute":true}}'
```
Retrieve the route:
```bash
oc get route default-route -n openshift-image-registry
```

### Mirror an External Image to the Internal Registry
```bash
oc image mirror docker.io/library/nginx:latest \
  image-registry.openshift-image-registry.svc:5000/myproject/nginx:latest
```

### Set Registry Resource Limits
```bash
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type merge \
  --patch '{"spec":{"resources":{"requests":{"memory":"1Gi"},"limits":{"memory":"2Gi"}}}}'
```

### Prune Old Images
```bash
oc adm prune images --confirm
```

### Force Garbage Collection on the Internal Registry
```bash
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type merge \
  --patch '{"spec":{"managementState":"Managed"}}'
```
Run garbage collection:
```bash
oc exec -n openshift-image-registry -it $(oc get pods -n openshift-image-registry -l docker-registry=default -o jsonpath='{.items[0].metadata.name}') -- registry garbage-collect /config.yml
```

---

## **OpenShift Container Platform Troubleshooting**

### Inspect all resources in a namespace
```bash
oc adm inspect ns/mynamespace
```

### Run cluster diagnostics
```bash
oc adm diagnostics
```

### Collect must-gather
```bash
oc adm must-gather
```

### Check status of the current project
```bash
oc status
```

### Get events for a project sorted by timestamp
```bash
oc get events --sort-by=.metadata.creationTimestamp
```

### Get events of type Warning
```bash
oc get ev --field-selector type=Warning -o jsonpath='{.items[].message}{"\n"}'
```

### Logs management

#### Get the logs of a specific pod
```bash
oc logs myrunning-pod-2-fdthn
```

#### Follow the logs of a specific pod
```bash
oc logs -f myrunning-pod-2-fdthn
```

#### Tail the logs of a specific pod
```bash
oc logs myrunning-pod-2-fdthn --tail=50
```

#### Check the integrated Docker registry logs
```bash
oc logs docker-registry-n-{xxxxx} -n default | less
```

### Create a temporary namespace to debug the node
```bash
oc debug node/master01
```

---

## **Security**

### Create a secret from the CLI
```bash
oc create secret generic oia-secret --from-literal=username=myuser \
--from-literal=password=mypassword
```

### Use secret in deployment env
```bash
oc set env deployment/ --from secret/oia-secret
```

### Mount the Secret on a Volume
```bash
oc set volumes dc/myapp --add --name=secret-volume --mount-path=/opt/app-root/ \
--secret-name=oia-secret
```

---


## **Certificates**

### Sign all pending Certificate Signing Requests (CSRs)
```bash
oc get csr -o name | xargs oc adm certificate approve
```

### Authenticate users using TLS certificates
1. Generate a private key and CSR:
   ```bash
   mkdir ${OCP_USERNAME}
   openssl req -new -nodes -subj "/CN=${OCP_USERNAME}" \
     -keyout ${OCP_USERNAME}/private.key -out ${OCP_USERNAME}/request.csr
   ```
2. Create a CertificateSigningRequest:
   ```bash
   cat <<EOF | oc apply -f -
   apiVersion: certificates.k8s.io/v1beta1
   kind: CertificateSigningRequest
   metadata:
     name: tls-auth-${OCP_USERNAME}
   spec:
     signerName: "kubernetes.io/kube-apiserver-client"
     request: $(cat ${OCP_USERNAME}/request.csr | base64 | tr -d '\n')
     usages:
       - digital signature
       - key encipherment
       - client auth
   EOF
   ```
3. Approve the CSR:
   ```bash
   oc adm certificate approve tls-auth-${OCP_USERNAME}
   ```

---

## **API**

### API Resources
List all API resources:
```bash
oc api-resources
```

### API resources per API group
```bash
oc api-resources --api-group config.openshift.io -o name
oc api-resources --api-group machineconfiguration.openshift.io -o name
```

### Explain resources
Explain resource details:
```bash
oc explain pods.spec.containers
```
For a specific API group:
```bash
oc explain --api-version=config.openshift.io/v1 scheduler
```

---

## **Miscellaneous Commands**

### Manage node state
```bash
oc adm manage node <node> --schedulable=false
```

### List installed operators
```bash
oc get csv
```

### Export resources as a template
```bash
oc export is,bc,dc,svc --as-template=app.yaml
```

### Show user in prompt
```bash
function ps1(){
  export PS1='[\u@\h($(oc whoami -c 2>/dev/null|cut -d/ -f3,1)) \W]\$ '
}
```

### Backup OpenShift objects
```bash
oc get all --all-namespaces --no-headers=true | awk '{print $1","$2}' | while read obj; do
  NS=$(echo $obj | cut -d, -f1)
  OBJ=$(echo $obj | cut -d, -f2)
  FILE=$(echo $obj | sed 's/\//-/g;s/,/-/g')
  echo $NS $OBJ $FILE
  oc export -n $NS $OBJ -o yaml > $FILE.yml
done
```
