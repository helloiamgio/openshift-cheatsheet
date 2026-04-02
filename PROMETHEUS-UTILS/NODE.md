# OpenShift Runbook

# Root Cause Analysis -- Node NotReady

**Version:** 1.0\
**Generated on:** 2026-02-19 13:49:14\
**Audience:** Operations / SRE / Platform Team

------------------------------------------------------------------------

# 1. Purpose

This runbook provides a structured procedure to identify the root cause
of an OpenShift node entering **NotReady** state.

It covers:

-   Node conditions analysis
-   Kubelet health validation
-   Resource pressure (CPU, Memory, Disk)
-   Storage and IO validation
-   Runtime (CRI-O) and Kubelet inspection
-   MachineConfigPool verification
-   Prometheus forensic queries

------------------------------------------------------------------------

# 2. Initial Setup

Set the node name:

``` bash
NODE=<node-name>
```

Example:

``` bash
NODE=ocp4-worker-0
```

------------------------------------------------------------------------

# 3. Step 1 -- Node Status & Conditions

``` bash
oc get node $NODE -o wide
oc describe node $NODE | sed -n '/Conditions:/,/Addresses:/p'
oc describe node $NODE | sed -n '/Events:/,$p'
```

### What to look for

-   Ready=False
-   KubeletNotReady
-   MemoryPressure=True
-   DiskPressure=True
-   PIDPressure=True
-   NetworkUnavailable=True

------------------------------------------------------------------------

# 4. Step 2 -- Kubelet Health (API Proxy Check)

``` bash
oc get --raw /api/v1/nodes/$NODE/proxy/healthz ; echo
oc get --raw /api/v1/nodes/$NODE/proxy/stats/summary | head
```

  Result        Interpretation
  ------------- ----------------------------
  Timeout       kubelet down / node frozen
  200 OK        kubelet running
  Stats error   runtime/storage issue

------------------------------------------------------------------------

# 5. Step 3 -- Node Debug Inspection

``` bash
oc debug node/$NODE -- chroot /host bash
```

Inside debug shell:

## 5.1 Reboot Check

``` bash
uptime
who -b
journalctl -b -1 -n 200 --no-pager
```

## 5.2 Memory Check

``` bash
free -m
vmstat 1 5
journalctl -k | egrep -i "oom|out of memory"
```

## 5.3 Disk & Inode Check

``` bash
df -hT
df -hi
```

Critical paths:

-   /
-   /var/lib/containers
-   /var/lib/kubelet

If usage \>85% → investigate immediately.

## 5.4 Storage / IO Errors

``` bash
journalctl -k | egrep -i "I/O error|blocked for more than|hung|reset|xfs|ext4"
```

## 5.5 Kubelet Logs

``` bash
journalctl -u kubelet -n 200 --no-pager
```

Look for:

-   PLEG is not healthy
-   Container runtime is down
-   DeadlineExceeded
-   Eviction manager errors

## 5.6 CRI-O Logs

``` bash
journalctl -u crio -n 200 --no-pager
```

Look for:

-   storage timeouts
-   overlay errors
-   rpc timeout

## 5.7 Runtime Check

``` bash
crictl ps -a
```

------------------------------------------------------------------------

# 6. Step 4 -- Cluster Resource Pressure

``` bash
oc adm top nodes
oc adm top pods -A --sort-by=memory | head -20
oc adm top pods -A --sort-by=cpu | head -20
```

------------------------------------------------------------------------

# 7. Step 5 -- MachineConfigPool

``` bash
oc get mcp
oc describe mcp worker
```

If:

-   Updating=True
-   Degraded=True

Node may be rebooting due to MCO update.

------------------------------------------------------------------------

# 8. Prometheus Investigation (Observe → Metrics)

## 8.1 Node Ready State

    kube_node_status_condition{condition="Ready"}

## 8.2 Nodes NotReady

    kube_node_status_condition{condition="Ready",status="false"}

## 8.3 Memory Usage %

    100 * (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes))

## 8.4 OOM Events

    increase(node_vmstat_oom_kill[1h])

## 8.5 Root Filesystem Usage

    100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100

## 8.6 Container Runtime Disk Usage

    100 - (node_filesystem_avail_bytes{mountpoint="/var/lib/containers"} / node_filesystem_size_bytes{mountpoint="/var/lib/containers"}) * 100

## 8.7 Disk IO Saturation

    rate(node_disk_io_time_seconds_total[5m])

## 8.8 Kubelet Restart Detection

    changes(process_start_time_seconds{job="kubelet"}[1h])

------------------------------------------------------------------------

# 9. Common Root Causes

  Symptom            Root Cause
  ------------------ -----------------------------
  healthz timeout    kubelet crash / node frozen
  OOM events         Memory exhaustion
  DiskPressure       Disk full
  IO wait high       Storage backend latency
  kubelet restarts   runtime crash
  MCP Updating       MCO-triggered reboot

------------------------------------------------------------------------

# 10. Escalation Guidance

Escalate to:

-   Infrastructure team → IO errors, storage latency, VM reboot
-   Application team → memory leaks, high CPU
-   Platform team → MCO degraded, kubelet crash loop

------------------------------------------------------------------------

# 11. Recommended Immediate Actions

If workload impacted:

``` bash
oc adm cordon $NODE
oc adm drain $NODE --ignore-daemonsets --delete-emptydir-data --force --grace-period=60 --timeout=10m
```

Then investigate offline.

------------------------------------------------------------------------

# 12. Documentation

When closing incident:

-   Capture Prometheus graphs
-   Attach kubelet logs
-   Attach df output
-   Document timeline (first NotReady occurrence)

------------------------------------------------------------------------

# END OF RUNBOOK
