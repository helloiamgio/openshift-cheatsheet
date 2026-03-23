# OpenShift + vSphere + ACM Troubleshooting Runbook

## 1. SSH nodes

``` bash
ssh core@<bootstrap-ip>
sudo -i
ssh core@<master-ip>
sudo -i
```

## 2. Bootstrap kubeconfig

``` bash
export KUBECONFIG=/etc/kubernetes/kubeconfig
oc get nodes -o wide
```

## 3. Bootstrap checks

``` bash
sudo crictl ps | grep etcd
systemctl status kubelet
journalctl -u kubelet -f
```

## 4. API connectivity

``` bash
curl -k https://api-int.<cluster>.<domain>:6443/healthz
nc -vz api-int.<cluster>.<domain> 6443
```

## 5. DNS

``` bash
cat /etc/resolv.conf
getent hosts api.<cluster>.<domain>
dig +short api-int.<cluster>.<domain>
```

## 6. Master kubeconfig

``` bash
cd /etc/kubernetes/static-pod-resources/kube-apiserver-certs/secrets/node-kubeconfigs
export KUBECONFIG=$(pwd)/lb-int.kubeconfig
oc whoami
```

## 7. Cluster status

``` bash
oc get nodes
oc get co
```

## 8. CSI troubleshooting

``` bash
oc get pods -n openshift-cluster-csi-drivers
oc logs -n openshift-cluster-csi-drivers <pod> -c csi-driver
oc logs -n openshift-cluster-csi-drivers <pod> -c vsphere-syncer
```

## 9. Identify failing containers

``` bash
oc get pod -n openshift-cluster-csi-drivers <pod> -o jsonpath='{range .status.containerStatuses[*]}{.name}{" ready="}{.ready}{" waiting="}{.state.waiting.reason}{" terminated="}{.lastState.terminated.reason}{"\n"}{end}'
```

## 10. Inspect CSI config

``` bash
oc get secret -n openshift-cluster-csi-drivers vsphere-csi-config-secret -o jsonpath='{.data.cloud\.conf}' | base64 -d
```

## 11. Inspect credentials

``` bash
oc get secret -n openshift-cluster-csi-drivers vmware-vsphere-cloud-credentials -o yaml
oc get secret -n openshift-cluster-csi-drivers vmware-vsphere-cloud-credentials -o jsonpath='{.data.agsvcs001\.agositafinco\.it\.username}' | base64 -d
```

## 12. Patch username

``` bash
NEW=$(printf '%s' 'SRV-OCP-PROD@agositafinco.it' | base64 -w0)

oc patch secret -n openshift-cluster-csi-drivers vmware-vsphere-cloud-credentials --type=merge -p "{\"data\":{\"agsvcs001.agositafinco.it.username\":\"$NEW\"}}"
```

## 13. Restart CSI

``` bash
oc delete pod -n openshift-cluster-csi-drivers --all
watch -n2 oc get pods -n openshift-cluster-csi-drivers
```

## 14. Verify storage operator

``` bash
oc get co storage
```

## 15. ACM Import

``` bash
kubectl apply -f import.yaml
```

## 16. ACM monitoring

``` bash
oc get managedcluster
watch -n2 oc get managedcluster ocp01-prod
```

## 17. Agents

``` bash
oc get pods -n open-cluster-management-agent
oc get pods -n open-cluster-management-agent-addon
```

## 18. Cleanup failed import

``` bash
oc delete klusterlet --all --ignore-not-found
oc delete ns open-cluster-management-agent --ignore-not-found
oc delete ns open-cluster-management-agent-addon --ignore-not-found
oc delete crd klusterlets.operator.open-cluster-management.io --ignore-not-found
oc delete crd klusterletaddonconfigs.agent.open-cluster-management.io --ignore-not-found
```

Hub:

``` bash
oc delete managedcluster ocp01-prod --ignore-not-found
oc delete ns ocp01-prod --ignore-not-found
oc delete klusterletaddonconfig ocp01-prod -n ocp01-prod --ignore-not-found
```

## 19. Final checks

``` bash
oc get nodes
oc get co
```
