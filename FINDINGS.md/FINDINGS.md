# Enterprise Bot DevOps Assessment - Part 4
## Kubernetes & Helm Troubleshooting Findings

**Candidate:** Gowtham  
**Assessment:** Part 4 – Kubernetes/Helm Debugging Lab

---

# Objective

The objective of this assessment was to troubleshoot and fix a broken Helm chart without modifying the application image or the cluster-state manifests. All fixes were implemented only within the Helm chart.

Verification command:

```bash
./scenario.sh verify
```

---

# Issue 1 – Backend Readiness Probe Failed

### Symptom

- Backend pod was running but never became Ready.
- Readiness probe continuously failed.

### Investigation

Executed:

```bash
kubectl describe pod <backend-pod> -n debug-lab
kubectl logs <backend-pod> -n debug-lab
```

Observed:

```
listening on :8081
```

while Kubernetes expected:

```
8080
```

### Root Cause

The application image listens on port **8081** by default unless the `PORT` environment variable is provided.

### Fix

Added the following environment variable:

```yaml
PORT: "8080"
```

Result:

- Backend became Ready.
- Health probe passed successfully.

---

# Issue 2 – Gateway Could Not Reach Backend

### Symptom

Gateway remained Not Ready.

Logs showed:

```
lookup backend.default.svc: no such host
```

### Investigation

Checked deployment configuration:

```bash
kubectl get deployment gateway -o yaml
```

Found:

```
BACKEND_URL=http://backend.default.svc:8080
```

### Root Cause

The backend service exists inside the **debug-lab** namespace.

Using `backend.default.svc` pointed to the wrong namespace.

### Fix

Updated:

```yaml
BACKEND_URL: http://backend:8080
```

Result:

- Gateway successfully connected to Backend.
- Gateway health endpoint became healthy.

---

# Issue 3 – Worker CrashLoopBackOff

### Symptom

Worker pod repeatedly restarted.

Logs:

```
mkdir /var/cache/app:
read-only file system
```

### Investigation

Executed:

```bash
kubectl logs <worker-pod>
```

### Root Cause

Container security policy enabled:

```yaml
readOnlyRootFilesystem: true
```

but the application required a writable cache directory.

### Fix

Mounted an `emptyDir` volume.

```yaml
volumes:
- name: cache
  emptyDir: {}

volumeMounts:
- name: cache
  mountPath: /var/cache/app
```

Result:

Worker started successfully.

---

# Issue 4 – Metrics Deployment Failed

### Symptom

Helm installation failed.

Error:

```
CPU request must be less than or equal to CPU limit
```

### Investigation

Reviewed:

```
values.yaml
```

### Root Cause

Resource requests exceeded configured limits.

### Fix

Adjusted resource values.

Example:

```yaml
requests:
  cpu: 100m

limits:
  cpu: 500m
```

Result:

Deployment created successfully.

---

# Issue 5 – Security Context Failure

### Symptom

Pods failed with:

```
CreateContainerConfigError
```

Error:

```
container has runAsNonRoot and image has non-numeric user
```

### Investigation

Executed:

```bash
kubectl describe pod
```

### Root Cause

The image specifies a named user.

Kubernetes could not verify it was non-root.

### Fix

Added:

```yaml
securityContext:
  runAsUser: 65532
  runAsNonRoot: true
```

Result:

Containers started successfully.

---

# Issue 6 – Reporter RBAC Misconfiguration

### Symptom

Reporter failed to access Kubernetes API.

Logs:

```
pods is forbidden
```

### Investigation

Verified permissions:

```bash
kubectl auth can-i list pods \
--as=system:serviceaccount:debug-lab:reporter
```

Inspected:

```bash
kubectl describe rolebinding
```

### Root Cause

RoleBinding referenced the wrong ServiceAccount namespace.

### Fix

Updated:

```yaml
subjects:
- kind: ServiceAccount
  name: reporter
  namespace: {{ .Release.Namespace }}
```

Result:

Reporter ServiceAccount received correct permissions.

---

# Issue 7 – Duplicate Helm Templates

### Symptom

Unexpected resources appeared during rendering.

Observed duplicate Deployments.

### Investigation

Executed:

```bash
helm template debug-lab ./broken-chart
```

### Root Cause

A leftover `template.yaml` generated duplicate Kubernetes objects.

### Fix

Removed the obsolete template file.

Result:

Only the intended resources were rendered.

---

# Troubleshooting Commands Used

```bash
kubectl get pods
kubectl describe pod
kubectl logs
kubectl get svc
kubectl get endpoints
kubectl get deployment -o yaml
kubectl auth can-i
kubectl get role
kubectl get rolebinding
helm template
helm upgrade --install
./scenario.sh verify
```

---

# Skills Demonstrated

- Kubernetes troubleshooting
- Helm template debugging
- Readiness/Liveness probe debugging
- Kubernetes networking
- Service discovery
- RBAC troubleshooting
- Resource management
- Security Context configuration
- Volume mounting
- Helm chart debugging
- Production incident investigation

---

# Summary

The lab required identifying and resolving multiple Kubernetes deployment issues without modifying the application image or cluster configuration. All fixes were implemented within the Helm chart by analyzing pod events, application logs, Kubernetes resources, RBAC configuration, and rendered Helm templates.

The troubleshooting approach focused on identifying the root cause of each failure rather than applying temporary fixes, following a production-style debugging workflow.