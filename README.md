# Frappe Helm Chart

A Helm chart to deploy a **Frappe Bench-like environment on Kubernetes**. This chart deploys Frappe and ERPNext using separate Kubernetes workloads for web requests, background jobs, scheduling, caching, and site management.

The chart supports external MariaDB/Galera, Valkey/Redis, persistent storage, multiple Frappe sites, automated site operations, and observability integrations.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Repository Structure](#repository-structure)
- [Installation](#installation)
- [Configuration](#configuration)
- [Deploying the Chart](#deploying-the-chart)
- [Creating a Frappe Site](#creating-a-frappe-site)
- [Managing Multiple Sites](#managing-multiple-sites)
- [Migrating a Site](#migrating-a-site)
- [Backup and Restore](#backup-and-restore)
- [Dropping a Site](#dropping-a-site)
- [Other Maintenance Operations](#other-maintenance-operations)
- [Observability](#observability)
- [Troubleshooting](#troubleshooting)
- [Useful Commands](#useful-commands)

---

## Overview

This Helm chart deploys a Frappe environment on Kubernetes with the following resources.

### ConfigMaps

- `nginx-config` — Overrides the default Nginx configuration for reverse proxying, static assets, and application requests.

### Deployments

- `gunicorn` — Handles Frappe application requests.
- `nginx` — Serves static assets and forwards application requests to Gunicorn.
- `worker-default` — Processes default background jobs.
- `worker-short` — Processes short-running background jobs.
- `worker-long` — Processes long-running background jobs.
- `scheduler` — Executes scheduled Frappe tasks.

### Services

- `nginx` — Exposes the application inside or outside the Kubernetes cluster.
- Additional internal services are configured according to the chart templates.

### Persistent Storage

- Worker PVC — Stores persistent Frappe site data and files.
- Additional storage can be configured through the chart values.

### Jobs

The chart provides Kubernetes Jobs for Frappe site and maintenance operations:

| Job                    | Purpose                                 |
| ---------------------- | --------------------------------------- |
| Configure              | Configure the Frappe environment        |
| Create Site            | Create a new Frappe site                |
| Create Multiple Sites  | Create multiple Frappe sites            |
| Drop Site              | Delete a Frappe site                    |
| Drop Multiple Sites    | Delete multiple Frappe sites            |
| Backup                 | Back up a Frappe site                   |
| Backup Multiple Sites  | Back up multiple sites                  |
| Migrate                | Run database and application migrations |
| Migrate Multiple Sites | Migrate multiple sites                  |
| Clear Cache            | Clear the Frappe cache                  |
| Redis Flush            | Flush Redis/Valkey data                 |
| Custom Job             | Execute custom commands                 |

---

## Architecture

```text
                     Users / Clients
                            |
                            v
                  Kubernetes Service
                            |
                            v
                     Nginx Deployment
                            |
                            v
                    Gunicorn Deployment
                            |
             +--------------+--------------+
             |              |              |
             v              v              v
        Worker Short   Worker Default   Worker Long
             |              |              |
             +--------------+--------------+
                            |
                            v
                      Valkey / Redis
                    Cache and Job Queue
                            |
                            v
                       Scheduler
                            |
                            v
                 External MariaDB/Galera
                            |
                            v
                  Persistent Site Files
```

### Application Components

| Component      | Responsibility                         |
| -------------- | -------------------------------------- |
| Nginx          | Reverse proxy and static asset serving |
| Gunicorn       | Frappe web application                 |
| Worker Short   | Short background tasks                 |
| Worker Default | Default background tasks               |
| Worker Long    | Long background tasks                  |
| Scheduler      | Scheduled jobs                         |
| Valkey/Redis   | Cache and background job queues        |
| MariaDB/Galera | Application database                   |
| PVC            | Persistent site data and files         |

---

## Prerequisites

Before deploying the chart, ensure the following are available.

- Kubernetes cluster
- Helm 3
- `kubectl` configured for the target cluster
- Frappe Docker image containing the required applications
- External MariaDB/Galera database
- Valkey/Redis cache and queue services
- Kubernetes StorageClass
- Kubernetes Ingress Controller or LoadBalancer implementation, if external access is required

### Verify the Environment

```bash
kubectl get nodes
kubectl get storageclass
helm version
kubectl version
```

### Example Environment

| Component     | Configuration                   |
| ------------- | ------------------------------- |
| Kubernetes    | Ubuntu kubeadm                  |
| Database      | External MariaDB/Galera         |
| Database IP   | `192.168.0.127`                 |
| Database Port | `3306`                          |
| Cache         | Valkey/Redis                    |
| Image         | `didin8080/frappe-build-test:1` |
| Namespace     | `erpnext`                       |
| Helm Chart    | Local Frappe Helm Chart         |

---

## Repository Structure

The chart repository contains the Helm templates and values required to deploy the Frappe environment.

```text
frappe-helm/
├── Chart.yaml
├── values.yaml
├── README.md
│
├── templates/
│   ├── configmap-nginx.yaml
│   ├── deployment-gunicorn.yaml
│   ├── deployment-nginx.yaml
│   ├── deployment-worker-default.yaml
│   ├── deployment-worker-short.yaml
│   ├── deployment-worker-long.yaml
│   ├── deployment-scheduler.yaml
│   ├── service-nginx.yaml
│   ├── pvc-worker.yaml
│   │
│   ├── job-configure.yaml
│   ├── job-create-site.yaml
│   ├── job-create-multiple-sites.yaml
│   ├── job-drop-site.yaml
│   ├── job-drop-multiple-sites.yaml
│   ├── job-backup.yaml
│   ├── job-backup-multiple-sites.yaml
│   ├── job-migrate.yaml
│   ├── job-migrate-multiple-sites.yaml
│   ├── job-clear-cache.yaml
│   ├── job-redis-flush.yaml
│   └── job-custom.yaml
│
└── ...
```

> The exact template filenames may vary depending on the current repository version.

---

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/didin2003/frappe-helm.git
cd frappe-helm
```

### 2. Create the Namespace

```bash
kubectl create namespace erpnext
```
add the privilege for thr namespace

```bash
kubectl label ns erpnext \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=privileged \
  pod-security.kubernetes.io/audit=privileged --overwrite
```

If the namespace already exists, Kubernetes will report that it is already present.

Verify:

```bash
kubectl get namespace erpnext
```

### 3. Configure Database Credentials

Create a Kubernetes Secret containing the database root password and the admin password.

```bash
kubectl create secret generic frappe-secret \
  --namespace erpnext \
  --from-literal=db-root-password='YOUR_DATABASE_ROOT_PASSWORD' \
  --from-literal=admin-password='admin_password'
```

Create a Kubernetes Secret containing the Redis Cache password and Queue Password.

```bash
kubectl create secret generic external-redis-credentials \
  -n erpnext \
  --from-literal=cache-password='YOUR_CACHE_PASSWORD' \
  --from-literal=queue-password='YOUR_QUEUE_PASSWORD'
```

Verify:

```bash
kubectl get secret frappe-secret -n erpnext
```

Create and Kubernetes Secret containining the sync_user, sync_password, radmin_user and radmin_password.

```bash
kubectl create secret generic proxysql-sync -n production \
  --from-literal=sync_user='<sync-user>' \
  --from-literal=sync_password='<sync-password>' \
  --from-literal=radmin_user='<radmin-user>' \
  --from-literal=radmin_password='<radmin-password>'
```
> Replace the example password with your actual database password. Avoid committing passwords to Git.

### 4. Verify Database Connectivity

From a Kubernetes pod with the MariaDB client:

```bash
mariadb -h 192.168.0.127 -P 3306 -u root -p
```

Verify that the database is reachable before creating a Frappe site.

---

## Configuration

The chart is configured through `values.yaml`.

### Application Image

```yaml
image:
  repository: didin8080/frappe-build-test
  tag: "1"
  pullPolicy: IfNotPresent
```

### Database Configuration

Configure the external MariaDB/Galera endpoint.

```yaml
# External database via ProxySQL
dbHost: "proxysql.database.svc.cluster.local"
dbPort: 6033
dbRootUser: "frappe_admin"
dbRootPassword: ""
dbRds: false
dbExistingSecret: "frappe-secret"
dbExistingSecretPasswordKey: "db-root-password"

# Direct Galera connection for site creation
galeraHost: "192.168.0.203"  #VIP for the Shared galera
galeraPort: 3306

# ---- Secret holding the ProxySQL sync credentials (must exist in this release's namespace) ----
# keys: sync_user, sync_password, radmin_user, radmin_password
proxysqlSync:
  existingSecret: "proxysql-sync"
```

The database root password is provided through the Kubernetes Secret.

### Valkey/Redis Configuration

Configure the external redis cache and queue endpoints according to the chart's Redis/Valkey values.

```yaml
externalRedis:
  cache:
    host: "192.168.1.151"
    port: 13000
    username: "default"
  queue:
    host: "192.168.1.152"
    port: 11000
    username: "default"
```

> Use the actual Redis/Valkey configuration keys defined in the current `values.yaml`.

### Persistent Storage

Example worker PVC configuration:

```yaml
persistence:
  worker:
    enabled: true
    # existingClaim: ""
    size: 8Gi
    storageClass: "ceph-cephfs"
    accessModes:
    - ReadWriteMany
```

Verify the available StorageClasses:

```bash
kubectl get storageclass
```

### Site Configuration

Site creation is managed through the Jobs section of `values.yaml`.

Example:

```yaml
jobs:
  createSite:
    enabled: false
    siteName: "erp.cluster.local"
```

Enable the relevant Job and configure its parameters before deployment.

---

## Deploying the Chart

### 1. Validate the Chart

```bash
helm lint .
```

### 2. Render the Kubernetes Manifests

```bash
helm template frappe . \
  --namespace erpnext \
  > /tmp/frappe-rendered.yaml
```

Review the generated manifests:

```bash
less /tmp/frappe-rendered.yaml
```

### 3. Install the Chart

```bash
helm upgrade --install frappe . \
  --namespace erpnext \
  --create-namespace
```

### 4. Verify the Deployment

```bash
kubectl get pods -n erpnext
kubectl get deployments -n erpnext
kubectl get services -n erpnext
kubectl get pvc -n erpnext
```

Check the Helm release:

```bash
helm list -n erpnext
```

---

## Creating a Frappe Site

A Frappe site is created using the chart's `createSite` or `createMultipleSites` Job.

### 1. Configure the Site

Edit `values.yaml`.

Example:

```yaml
jobs:
  createSite:
    enabled: true
    siteName: "erp.cluster.local"
```

Configure the remaining site parameters, including administrator password, database credentials, and installed applications, according to the chart's Job template.

### 2. Deploy the Site Creation Job

```bash
helm upgrade frappe . -n erpnext
```

### 3. Check the Job

```bash
kubectl get jobs -n erpnext
```

Get the Job name:

```bash
kubectl get jobs -n erpnext
```

View its logs:

```bash
kubectl logs job/<JOB_NAME> -n erpnext
```

### 4. Verify the Site

```bash
kubectl exec -it deployment/gunicorn -n erpnext -- \
  bench --site erp.cluster.local list-apps
```

Expected applications may include:

```text
frappe
erpnext
hrms
payments
```

> Use the actual site name configured in your deployment.

---

## Managing Multiple Sites

The chart supports creating multiple Frappe sites through `createMultipleSites`.

### Example Configuration

```yaml
jobs:
  createMultipleSites:
    enabled: true
    sites:
      - site1.test
      - site2.test
```

Configure the remaining parameters according to the current Job template.

Deploy:

```bash
helm upgrade --install frappe . \
  --namespace erpnext
```

Verify:

```bash
kubectl get jobs -n erpnext
```

Check the Job logs:

```bash
kubectl logs job/<JOB_NAME> -n erpnext
```

### Important

Creating a site is a one-time operation for each new site.

Do not repeatedly enable site creation during normal Helm upgrades. Disable the Job after successful completion to avoid unnecessary or duplicate site creation attempts.

---

## Migrating a Site

The `migrate` Job executes Frappe migrations for an existing site.

Migrations may be required after:

- Updating Frappe or ERPNext versions
- Installing a new application
- Updating application code
- Changing DocTypes or database schemas

### 1. Configure the Migration Job

Edit `values.yaml`.

```yaml
jobs:
  migrate:
    enabled: true
    siteName: "erp.cluster.local"
```

### 2. Deploy the Migration Job

```bash
helm upgrade frappe . -n erpnext
```

### 3. Monitor the Migration

```bash
kubectl get jobs -n erpnext
```

View logs:

```bash
kubectl logs job/<JOB_NAME> -n erpnext
```

### 4. Verify the Migration

```bash
kubectl exec -it deployment/gunicorn -n erpnext -- \
  bench --site erp.cluster.local list-apps
```

### Migrating Multiple Sites

The chart also supports `migrateMultipleSites`.

Configure the required sites in `values.yaml` and enable the corresponding Job.

```yaml
jobs:
  migrateMultipleSites:
    enabled: true
```

Deploy and monitor the Job using the same commands described above.

> Always take a database and site-file backup before running migrations in production.

---

## Backup and Restore

The chart provides backup Jobs for individual and multiple sites.

### Backup a Single Site

Configure:

```yaml
jobs:
  backup:
    enabled: true
    siteName: "erp.cluster.local"
```

Deploy:

```bash
helm upgrade frappe . -n erpnext
```

Check the Job:

```bash
kubectl get jobs -n erpnext
```

View logs:

```bash
kubectl logs job/<JOB_NAME> -n erpnext
```

### Backup Multiple Sites

Configure the `backupMultipleSites` Job in `values.yaml`.

```yaml
jobs:
  backupMultipleSites:
    enabled: true
```

Deploy and verify the Job.

### Restore a Site

A typical Frappe restore process includes:

1. Identify the target site.
2. Locate the database backup.
3. Locate the public and private files backup.
4. Ensure the target site exists or prepare a new site.
5. Restore the database and files.
6. Run migrations if required.
7. Verify the application.

Example command executed inside the application container:

```bash
bench --site erp.cluster.local restore /path/to/database-backup.sql.gz
```

Restore public and private files using the corresponding backup files and Frappe restore options.

> Ensure the backup files are accessible inside the container and that the database credentials are correct. The exact restore procedure depends on the backup format and target site state.

---

## Dropping a Site

The chart provides `dropSite` and `dropMultipleSites` Jobs.

**Warning:** Dropping a site is destructive. Take a backup before proceeding.

### Drop a Single Site

Configure:

```yaml
jobs:
  dropSite:
    enabled: true
    forced: false
    siteName: "erp.cluster.local"
```

Deploy:

```bash
helm upgrade frappe . -n erpnext
```

Check the Job:

```bash
kubectl get jobs -n erpnext
```

View logs:

```bash
kubectl logs job/<JOB_NAME> -n erpnext
```

### Drop Multiple Sites

Configure the `dropMultipleSites` Job with the target site names.

Enable the Job only when the sites are intended to be deleted.

### Important

- Verify the site name before executing the Job.
- Ensure a valid backup exists.
- Do not enable site deletion during regular Helm upgrades.
- Review the `forced` setting before executing the Job.

---

## Other Maintenance Operations

### Clear Cache

The `clearCache` Job clears the cache for the specified site.

Configure the Job in `values.yaml`, enable it, and deploy the Helm release.

### Redis/Valkey Flush

The `redisFlush` Job is available for Redis/Valkey maintenance.

**Warning:** Flushing Redis/Valkey may affect multiple sites and background jobs if the same Redis instance is shared.

Use this operation only after understanding the impact on the environment.

### Custom Job

The chart provides a custom Job for executing additional Frappe commands.

Use it for maintenance operations that are not covered by the predefined Jobs.

Configure the command and parameters according to the current Job template.

---

## Observability

Observability provides visibility into application health, performance, resource consumption, and failures.

The chart can be monitored using Kubernetes-native tools and external observability platforms.

### 1. Kubernetes Resource Monitoring

Check the status of all application components.

```bash
kubectl get pods -n erpnext
kubectl get deployments -n erpnext
kubectl get jobs -n erpnext
kubectl get pvc -n erpnext
```

### 2. Application Logs

Nginx logs:

```bash
kubectl logs deployment/nginx -n erpnext
```

Gunicorn logs:

```bash
kubectl logs deployment/gunicorn -n erpnext
```

Worker logs:

```bash
kubectl logs deployment/worker-default -n erpnext
kubectl logs deployment/worker-short -n erpnext
kubectl logs deployment/worker-long -n erpnext
```

Scheduler logs:

```bash
kubectl logs deployment/scheduler -n erpnext
```

### 3. Resource Utilization

If Metrics Server is installed:

```bash
kubectl top pods -n erpnext
kubectl top nodes
```

### 4. Job Monitoring

Monitor the status of site creation, migration, backup, and maintenance Jobs.

```bash
kubectl get jobs -n erpnext
kubectl describe job <JOB_NAME> -n erpnext
kubectl logs job/<JOB_NAME> -n erpnext
```

### 5. Persistent Storage Monitoring

```bash
kubectl get pvc -n erpnext
kubectl describe pvc <PVC_NAME> -n erpnext
```

### 6. Prometheus and Grafana

For production observability, Prometheus and Grafana can be used to monitor:

- Kubernetes node and pod metrics
- CPU and memory utilization
- PVC utilization
- Application availability
- Job failures
- Background worker health
- Redis/Valkey metrics
- MariaDB/Galera metrics

The required exporters, ServiceMonitors, dashboards, and alert rules must be configured according to the observability stack deployed in the cluster.

---

## Troubleshooting

### Pod is in Pending State

Check:

```bash
kubectl describe pod <POD_NAME> -n erpnext
kubectl get pvc -n erpnext
kubectl get storageclass
```

Common causes:

- PVC cannot be bound
- Insufficient CPU or memory
- Node scheduling constraints
- Missing StorageClass

### Pod is in CrashLoopBackOff

Check:

```bash
kubectl logs <POD_NAME> -n erpnext
kubectl logs <POD_NAME> -n erpnext --previous
kubectl describe pod <POD_NAME> -n erpnext
```

Common causes:

- Incorrect database credentials
- Database connectivity failure
- Redis/Valkey connectivity failure
- Incorrect application configuration
- Missing site configuration

### Site Creation Job Failed

Check:

```bash
kubectl get jobs -n erpnext
kubectl describe job <JOB_NAME> -n erpnext
kubectl logs job/<JOB_NAME> -n erpnext
```

Verify:

- Database connectivity
- Database credentials
- Site name
- Application image
- Persistent storage
- Redis/Valkey connectivity

### Database Connection Failure

Verify connectivity to the database:

```bash
nc -zv 192.168.0.127 3306
```

Check the database configuration and credentials in the Kubernetes Secret.

### Helm Upgrade Issues

Validate the chart:

```bash
helm lint .
```

Render the manifests:

```bash
helm template frappe . \
  --namespace erpnext
```

Check the release:

```bash
helm status frappe -n erpnext
helm history frappe -n erpnext
```

---

## Useful Commands

| Operation         | Command                                      |
| ----------------- | -------------------------------------------- |
| Validate chart    | `helm lint .`                                |
| Render manifests  | `helm template frappe . -n erpnext`          |
| Install chart     | `helm upgrade --install frappe . -n erpnext` |
| Check release     | `helm status frappe -n erpnext`              |
| List releases     | `helm list -n erpnext`                       |
| List pods         | `kubectl get pods -n erpnext`                |
| List deployments  | `kubectl get deployments -n erpnext`         |
| List services     | `kubectl get svc -n erpnext`                 |
| List Jobs         | `kubectl get jobs -n erpnext`                |
| List PVCs         | `kubectl get pvc -n erpnext`                 |
| View pod logs     | `kubectl logs <POD_NAME> -n erpnext`         |
| View Job logs     | `kubectl logs job/<JOB_NAME> -n erpnext`     |
| Describe pod      | `kubectl describe pod <POD_NAME> -n erpnext` |
| Uninstall release | `helm uninstall frappe -n erpnext`           |

---

## Important Operational Guidelines

1. Always take backups before migrations or destructive operations.
2. Enable site creation Jobs only when creating new sites.
3. Disable one-time Jobs after successful execution.
4. Keep database credentials in Kubernetes Secrets.
5. Ensure persistent storage is available before deploying the application.
6. Verify external database and Redis/Valkey connectivity.
7. Review rendered Helm manifests before applying production changes.
8. Monitor application pods, Jobs, storage, and resource utilization.
9. Use version-compatible Frappe, ERPNext, and custom application images.
10. Validate all configuration changes in a test environment before applying them to production.

---

## Repository


**Purpose:** Deploy and manage Frappe/ERPNext environments on Kubernetes using Helm.
