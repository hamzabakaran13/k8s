# Kubernetes The Hard Way (AWS) --- Phase 1 & Phase 2 (PKI) Notes

> **Scope:** This document covers everything completed so far:
>
> -   **Phase 1:** OS, kernel, sysctl, container runtime (containerd)
> -   **Phase 2 (in progress):** PKI (CA + initial certificates) and
>     hostname standardization
>
> **Applies to:** **ALL** nodes unless explicitly stated.
>
> -   Control Plane: **cp-1, cp-2, cp-3**
> -   Workers: **wk-1, wk-2, wk-3**
>
> **Access method:** AWS SSM Session Manager (no SSH)

------------------------------------------------------------------------

## Phase 1 --- OS, Kernel & Container Runtime Preparation

### 🎯 Goal

Prepare all EC2 instances for a fully manual Kubernetes installation:

-   ❌ No `kubeadm`
-   ❌ No EKS
-   ❌ No managed control plane
-   ✅ 100% manual setup

This phase ensures the Linux kernel, networking stack, and container
runtime are ready before Kubernetes components are installed.

------------------------------------------------------------------------

## 1️⃣ Disable Swap (Mandatory)

Kubernetes (kubelet) expects stable, predictable memory management. With
swap enabled, kubelet may refuse to start or behave inconsistently.

### ✅ Verify swap is disabled

``` bash
swapon --show
```

Must return **no output**.

``` bash
free -h
```

Expected:

    Swap: 0B  0B  0B

### ❌ If swap is enabled

``` bash
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

This: - Disables swap immediately - Prevents swap from enabling after
reboot

------------------------------------------------------------------------

## 2️⃣ Load Required Kernel Modules

These kernel modules are required for Kubernetes networking and for
container image filesystem layering.

### 2.1️⃣ `br_netfilter`

#### Load

``` bash
sudo modprobe br_netfilter
```

#### Verify

``` bash
lsmod | grep br_netfilter
```

Expected:

    br_netfilter  ...
    bridge        ... br_netfilter

#### 🧠 Why `br_netfilter`?

Kubernetes networking (CNI + kube-proxy) relies heavily on **iptables**
rules. Pod networking often uses Linux bridges --- by default, bridged
traffic may bypass iptables. `br_netfilter` enables bridged traffic to
be processed by iptables, allowing:

-   Service routing (kube-proxy iptables rules)
-   ClusterIP + NAT behavior
-   NetworkPolicies (iptables-based)

Without it: - Service routing breaks - kube-proxy rules can be ignored -
debugging networking becomes painful later

------------------------------------------------------------------------

### 2.2️⃣ `overlay`

#### Load

``` bash
sudo modprobe overlay
```

#### Verify

``` bash
lsmod | grep overlay
```

Expected:

    overlay  ...

#### 🧠 Why `overlay`?

containerd typically uses **OverlayFS** (overlay snapshotter) to mount
container image layers. Without the overlay module:

-   container image layers can't mount
-   containers/pods fail to start
-   you may see mount-related errors

------------------------------------------------------------------------

## 3️⃣ Make Kernel Modules Persistent (across reboot)

If you only run `modprobe`, the modules are loaded **only until
reboot**. Persist them:

``` bash
echo br_netfilter | sudo tee /etc/modules-load.d/k8s.conf
echo overlay | sudo tee -a /etc/modules-load.d/k8s.conf
```

Verify:

``` bash
cat /etc/modules-load.d/k8s.conf
```

Expected:

    br_netfilter
    overlay

------------------------------------------------------------------------

## 4️⃣ Sysctl Networking Configuration

These sysctl values are required for Kubernetes networking to function
correctly.

Run on **all nodes**:

``` bash
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
```

Apply immediately (no reboot):

``` bash
sudo sysctl --system
```

Verify:

``` bash
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.bridge.bridge-nf-call-ip6tables
sysctl net.ipv4.ip_forward
```

All must return:

    = 1

### 🧠 Why these settings?

  -----------------------------------------------------------------------------
  Setting                                   Purpose
  ----------------------------------------- -----------------------------------
  `net.ipv4.ip_forward=1`                   Enables routing/forwarding between
                                            interfaces (required for cross-node
                                            Pod traffic)

  `net.bridge.bridge-nf-call-iptables=1`    Ensures bridged traffic is
                                            filtered/handled by iptables
                                            (kube-proxy + CNI)

  `net.bridge.bridge-nf-call-ip6tables=1`   Same behavior for IPv6 (safe to set
                                            even if not using IPv6)
  -----------------------------------------------------------------------------

Without these, Services and cross-node Pod networking can fail in
non-obvious ways.

------------------------------------------------------------------------

## 5️⃣ Install Container Runtime (containerd)

Kubernetes needs a CRI-compatible runtime. We are using **containerd**
(not Docker).

Run on **all nodes**.

### 5.1️⃣ Install

``` bash
sudo apt update
sudo apt install -y containerd
```

### 5.2️⃣ Generate default config

``` bash
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
```

### 5.3️⃣ Use systemd cgroup driver (CRITICAL)

Kubelet uses **systemd** cgroups by default on Ubuntu. containerd must
match.

``` bash
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

Verify:

``` bash
grep SystemdCgroup /etc/containerd/config.toml
```

Must show:

    SystemdCgroup = true

If containerd uses `cgroupfs`, kubelet will later fail with a **cgroup
driver mismatch**.

### 5.4️⃣ Enable and start containerd

``` bash
sudo systemctl enable containerd
sudo systemctl restart containerd
```

Verify:

``` bash
systemctl is-active containerd
```

Expected:

    active

### 5.5️⃣ Verify CRI socket

``` bash
ls -l /run/containerd/containerd.sock
```

If the socket exists, containerd is operational.

------------------------------------------------------------------------

## ✅ Phase 1 Validation Checklist (run anywhere)

``` bash
echo "---- SWAP ----"
swapon --show

echo "---- MEMORY ----"
free -h

echo "---- BR_NETFILTER ----"
lsmod | grep br_netfilter

echo "---- OVERLAY ----"
lsmod | grep overlay

echo "---- SYSCTL ----"
sysctl net.ipv4.ip_forward

echo "---- CONTAINERD ----"
systemctl is-active containerd

echo "---- CRI SOCKET ----"
ls -l /run/containerd/containerd.sock
```

All nodes must satisfy: - Swap disabled - `br_netfilter` + `overlay`
loaded (and persistent) - Sysctl values set to `1` - containerd active -
CRI socket present

------------------------------------------------------------------------

## ✅ Phase 1 Complete

### 🚀 Next Phase: PKI & Certificate Authority Setup (Phase 2)

------------------------------------------------------------------------

# Phase 2 (in progress) --- PKI (CA + Initial Certificates)

> **All PKI generation is done on `cp-1`**, then certificates will be
> distributed to other nodes later (SSM-only environment).

------------------------------------------------------------------------

## 0️⃣ Install cfssl tooling (cp-1 only)

We use cfssl for CA + certificate generation (Hard Way style).

``` bash
sudo apt install -y golang-cfssl
cfssl version
```

------------------------------------------------------------------------

## 1️⃣ Create PKI working directory (cp-1 only)

``` bash
mkdir -p ~/k8s-pki
cd ~/k8s-pki
pwd
```

Expected path:

    /home/ssm-user/k8s-pki

------------------------------------------------------------------------

## 2️⃣ CA Configuration (cp-1 only)

Defines certificate signing profiles (valid for \~10 years).

``` bash
cat > ca-config.json <<EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": ["signing", "key encipherment", "server auth", "client auth"],
        "expiry": "87600h"
      }
    }
  }
}
EOF
```

------------------------------------------------------------------------

## 3️⃣ CA CSR (Certificate Signing Request) (cp-1 only)

``` bash
cat > ca-csr.json <<EOF
{
  "CN": "Kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BA",
      "L": "Sarajevo",
      "O": "Kubernetes",
      "OU": "CA",
      "ST": "Federation"
    }
  ]
}
EOF
```

------------------------------------------------------------------------

## 4️⃣ Generate Root CA (cp-1 only)

``` bash
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
```

Expected output files:

-   `ca.pem`
-   `ca-key.pem`
-   `ca.csr`

Verify:

``` bash
ls -l
```

------------------------------------------------------------------------

## 5️⃣ Cluster addressing inputs (used for SAN)

### Control plane node IPs

-   **cp-1 → 10.0.2.68**
-   **cp-2 → 10.0.2.254**
-   **cp-3 → 10.0.2.5**

### HA API endpoint (NLB DNS)

-   `kthw-aws-api-9ac6d94e55bf410b.elb.us-east-1.amazonaws.com`

### Service CIDR (Hard Way default)

We follow the Hard Way default:

-   Service CIDR: `10.32.0.0/24`
-   Kubernetes Service IP: `10.32.0.1`

------------------------------------------------------------------------

## 6️⃣ Generate kube-apiserver certificate (cp-1 only)

### 6.1 Create CSR

``` bash
cat > kube-apiserver-csr.json <<EOF
{
  "CN": "kube-apiserver",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BA",
      "L": "Sarajevo",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Federation"
    }
  ]
}
EOF
```

### 6.2 Generate cert with correct SANs

> SANs must include: NLB DNS, CP IPs, Kubernetes service DNS, and the
> Kubernetes service IP.

``` bash
cfssl gencert   -ca=ca.pem   -ca-key=ca-key.pem   -config=ca-config.json   -profile=kubernetes   -hostname=10.32.0.1,10.0.2.68,10.0.2.254,10.0.2.5,kthw-aws-api-9ac6d94e55bf410b.elb.us-east-1.amazonaws.com,127.0.0.1,kubernetes,kubernetes.default,kubernetes.default.svc,kubernetes.default.svc.cluster.local   kube-apiserver-csr.json | cfssljson -bare kube-apiserver
```

### 6.3 Verify SANs (IMPORTANT)

``` bash
openssl x509 -in kube-apiserver.pem -noout -text | grep -A1 "Subject Alternative Name"
```

You must see: - NLB DNS - all CP IPs - `10.32.0.1` - Kubernetes DNS
names - `127.0.0.1`

------------------------------------------------------------------------

## 7️⃣ Generate etcd certificate (cp-1 only)

### 7.1 Create CSR

``` bash
cat > etcd-server-csr.json <<EOF
{
  "CN": "etcd",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "BA",
      "L": "Sarajevo",
      "O": "Kubernetes",
      "OU": "Kubernetes The Hard Way",
      "ST": "Federation"
    }
  ]
}
EOF
```

### 7.2 Generate cert with SANs (CP IPs + localhost)

``` bash
cfssl gencert   -ca=ca.pem   -ca-key=ca-key.pem   -config=ca-config.json   -profile=kubernetes   -hostname=10.0.2.68,10.0.2.254,10.0.2.5,127.0.0.1   etcd-server-csr.json | cfssljson -bare etcd-server
```

### 7.3 Verify SANs

``` bash
openssl x509 -in etcd-server.pem -noout -text | grep -A1 "Subject Alternative Name"
```

------------------------------------------------------------------------

## 8️⃣ Generate client certificates (cp-1 only)

> These are **client certs** (not server certs).\
> cfssl warnings about missing `hosts` are expected and safe to ignore.

### 8.1 kube-controller-manager

``` bash
cat > kube-controller-manager-csr.json <<EOF
{
  "CN": "system:kube-controller-manager",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [
    { "C": "BA", "L": "Sarajevo", "O": "system:kube-controller-manager", "OU": "Kubernetes The Hard Way", "ST": "Federation" }
  ]
}
EOF

cfssl gencert   -ca=ca.pem   -ca-key=ca-key.pem   -config=ca-config.json   -profile=kubernetes   kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
```

### 8.2 kube-scheduler

``` bash
cat > kube-scheduler-csr.json <<EOF
{
  "CN": "system:kube-scheduler",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [
    { "C": "BA", "L": "Sarajevo", "O": "system:kube-scheduler", "OU": "Kubernetes The Hard Way", "ST": "Federation" }
  ]
}
EOF

cfssl gencert   -ca=ca.pem   -ca-key=ca-key.pem   -config=ca-config.json   -profile=kubernetes   kube-scheduler-csr.json | cfssljson -bare kube-scheduler
```

### 8.3 admin (kubectl)

``` bash
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [
    { "C": "BA", "L": "Sarajevo", "O": "system:masters", "OU": "Kubernetes The Hard Way", "ST": "Federation" }
  ]
}
EOF

cfssl gencert   -ca=ca.pem   -ca-key=ca-key.pem   -config=ca-config.json   -profile=kubernetes   admin-csr.json | cfssljson -bare admin
```

------------------------------------------------------------------------

# Hostname Standardization (recommended)

We standardize hostnames so kubelet node names match our intended
naming.

-   Control plane: `cp-1`, `cp-2`, `cp-3`
-   Workers: `wk-1`, `wk-2`, `wk-3`

Run on each node (matching the node):

## Control plane

``` bash
sudo hostnamectl set-hostname cp-1
sudo hostnamectl set-hostname cp-2
sudo hostnamectl set-hostname cp-3
```

## Workers

``` bash
sudo hostnamectl set-hostname wk-1
sudo hostnamectl set-hostname wk-2
sudo hostnamectl set-hostname wk-3
```

Verify:

``` bash
hostname
```

> Note: you may need to reconnect your SSM session (or open a new one)
> to see the updated hostname in the prompt.

------------------------------------------------------------------------

------------------------------------------------------------------------

## 📌 Cluster Topology

### Control Plane

-   **cp-1** → 10.0.2.68\
-   **cp-2** → 10.0.2.254\
-   **cp-3** → 10.0.2.5

### Workers

-   **wk-1** → 10.0.2.10\
-   **wk-2** → 10.0.2.142\
-   **wk-3** → 10.0.2.236

------------------------------------------------------------------------

# 1️⃣ Current PKI Status (cp-1)

Certificates created on `cp-1` inside `~/k8s-pki`:

-   `ca.pem`, `ca-key.pem`
-   `kube-apiserver.pem`, `kube-apiserver-key.pem`
-   `etcd-server.pem`, `etcd-server-key.pem`
-   `kube-controller-manager.pem`, `kube-controller-manager-key.pem`
-   `kube-scheduler.pem`, `kube-scheduler-key.pem`
-   `admin.pem`, `admin-key.pem`

> ⚠ At this stage certificates were only present on **cp-1** and not yet
> distributed.

------------------------------------------------------------------------

# 2️⃣ Generate kube-proxy Certificate (cp-1)

The kube-proxy authenticates as `system:kube-proxy`.

``` bash
cat > kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [
    { "C": "BA", "L": "Sarajevo", "O": "system:node-proxier", "OU": "Kubernetes The Hard Way", "ST": "Federation" }
  ]
}
EOF

cfssl gencert   -ca=ca.pem   -ca-key=ca-key.pem   -config=ca-config.json   -profile=kubernetes   kube-proxy-csr.json | cfssljson -bare kube-proxy
```

Verify:

``` bash
ls -l kube-proxy*
```

------------------------------------------------------------------------

# 3️⃣ Generate Kubelet Certificates (cp-1)

Each node must authenticate as:

    system:node:<hostname>

-   CN = `system:node:<hostname>`
-   O = `system:nodes`
-   SAN must include hostname + IP

Create folder:

``` bash
mkdir -p kubelets
```

Batch generation:

``` bash
for NODE in cp-1 cp-2 cp-3 wk-1 wk-2 wk-3; do
  case ${NODE} in
    cp-1) IP="10.0.2.68" ;;
    cp-2) IP="10.0.2.254" ;;
    cp-3) IP="10.0.2.5" ;;
    wk-1) IP="10.0.2.10" ;;
    wk-2) IP="10.0.2.142" ;;
    wk-3) IP="10.0.2.236" ;;
  esac

  cat > kubelets/${NODE}-csr.json <<EOF
{
  "CN": "system:node:${NODE}",
  "key": { "algo": "rsa", "size": 2048 },
  "names": [
    { "C": "BA", "L": "Sarajevo", "O": "system:nodes", "OU": "Kubernetes The Hard Way", "ST": "Federation" }
  ]
}
EOF

  cfssl gencert     -ca=ca.pem     -ca-key=ca-key.pem     -config=ca-config.json     -profile=kubernetes     -hostname=${NODE},${IP}     kubelets/${NODE}-csr.json | cfssljson -bare kubelets/${NODE}
done
```

Verify SAN example:

``` bash
openssl x509 -in kubelets/wk-1.pem -noout -text | grep -A1 "Subject Alternative Name"
```

Expected:

    DNS:wk-1
    IP Address:10.0.2.10

------------------------------------------------------------------------

# 4️⃣ Encryption at Rest (cp-1)

Generate encryption configuration for Kubernetes Secrets stored in etcd.

``` bash
ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

cat > encryption-config.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${ENCRYPTION_KEY}
      - identity: {}
EOF
```

------------------------------------------------------------------------

# 5️⃣ Install kubectl (cp-1)

``` bash
cd /tmp
curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
kubectl version --client
```

------------------------------------------------------------------------

# 6️⃣ Generate kubeconfig Files (cp-1)

API endpoint (NLB):

``` bash
API_SERVER="https://kthw-aws-api-9ac6d94e55bf410b.elb.us-east-1.amazonaws.com:6443"
```

Kubeconfigs created for:

-   admin
-   kube-controller-manager
-   kube-scheduler
-   kube-proxy
-   6 kubelets

------------------------------------------------------------------------

# 7️⃣ Create Required Directories

### Control Plane Nodes

``` bash
sudo mkdir -p /etc/kubernetes/pki /var/lib/kubernetes
sudo chown -R root:root /etc/kubernetes /var/lib/kubernetes
```

### Worker Nodes

``` bash
sudo mkdir -p /etc/kubernetes/pki /var/lib/kubelet /var/lib/kube-proxy
sudo chown -R root:root /etc/kubernetes /var/lib/kubelet /var/lib/kube-proxy
```

------------------------------------------------------------------------

# 8️⃣ Bundle & Distribute Certificates

On `cp-1`:

``` bash
mkdir -p bundles/cp bundles/wk-1 bundles/wk-2 bundles/wk-3
```

Control Plane bundle includes:

-   CA
-   API server certs
-   etcd certs
-   controller & scheduler certs
-   encryption config
-   admin + component kubeconfigs

Workers receive:

-   CA
-   kube-proxy cert + kubeconfig
-   kubelet cert + kubeconfig

------------------------------------------------------------------------

# 9️⃣ Base64 Transfer to cp-2 / cp-3

On cp-1:

``` bash
base64 -w0 cp-bundle.tar.gz > /tmp/cp-bundle.b64
```

On cp-2 / cp-3:

``` bash
base64 -d /tmp/cp-bundle.b64 > /tmp/cp-bundle.tar.gz
sudo tar -xzf /tmp/cp-bundle.tar.gz -C /tmp
```

Install certificates only after verifying extracted files exist.

------------------------------------------------------------------------

# ✅ Verification

``` bash
ls -la /etc/kubernetes/pki
ls -la /var/lib/kubernetes
```

# Kubernetes The Hard Way --- PKI Distribution & Control Plane Setup (AWS)

------------------------------------------------------------------------

## 7️⃣ Create Required Directories

### 🔹 Control Plane Nodes (cp-1 / cp-2 / cp-3)

``` bash
sudo mkdir -p /etc/kubernetes/pki /var/lib/kubernetes
sudo chown -R root:root /etc/kubernetes /var/lib/kubernetes
```

These directories store:

-   Kubernetes control plane certificates
-   Component kubeconfig files
-   Encryption configuration file
-   Service account signing key

------------------------------------------------------------------------

### 🔹 Worker Nodes (wk-1 / wk-2 / wk-3)

``` bash
sudo mkdir -p /etc/kubernetes/pki /var/lib/kubelet /var/lib/kube-proxy
sudo chown -R root:root /etc/kubernetes /var/lib/kubelet /var/lib/kube-proxy
```

These directories store:

-   CA certificate
-   Kubelet certificates and kubeconfig
-   Kube-proxy certificates and kubeconfig

------------------------------------------------------------------------

## 8️⃣ Bundle & Distribute Certificates

On **cp-1**, create bundle directories:

``` bash
mkdir -p bundles/cp bundles/wk-1 bundles/wk-2 bundles/wk-3
```

### 🔹 Control Plane Bundle Includes

-   ca.pem
-   ca-key.pem
-   kube-apiserver.pem
-   kube-apiserver-key.pem
-   etcd-server.pem
-   etcd-server-key.pem
-   kube-controller-manager.pem
-   kube-controller-manager-key.pem
-   kube-scheduler.pem
-   kube-scheduler-key.pem
-   encryption-config.yaml
-   admin.kubeconfig
-   kube-controller-manager.kubeconfig
-   kube-scheduler.kubeconfig

------------------------------------------------------------------------

## 9️⃣ Base64 Transfer --- Control Plane Nodes

### 🔹 On cp-1

``` bash
base64 -w0 cp-bundle.tar.gz > /tmp/cp-bundle.b64
```

### 🔹 On cp-2 / cp-3

``` bash
base64 -d /tmp/cp-bundle.b64 > /tmp/cp-bundle.tar.gz
sudo tar -xzf /tmp/cp-bundle.tar.gz -C /tmp
```

------------------------------------------------------------------------

## 🔹 Install Control Plane Certificates

``` bash
sudo install -m 0644 /tmp/cp/ca.pem /etc/kubernetes/pki/ca.pem
sudo install -m 0600 /tmp/cp/ca-key.pem /etc/kubernetes/pki/ca-key.pem

sudo install -m 0644 /tmp/cp/kube-apiserver.pem /etc/kubernetes/pki/kube-apiserver.pem
sudo install -m 0600 /tmp/cp/kube-apiserver-key.pem /etc/kubernetes/pki/kube-apiserver-key.pem

sudo install -m 0644 /tmp/cp/etcd-server.pem /etc/kubernetes/pki/etcd-server.pem
sudo install -m 0600 /tmp/cp/etcd-server-key.pem /etc/kubernetes/pki/etcd-server-key.pem

sudo install -m 0600 /tmp/cp/encryption-config.yaml /var/lib/kubernetes/encryption-config.yaml
sudo install -m 0600 /tmp/cp/admin.kubeconfig /var/lib/kubernetes/admin.kubeconfig
```

All private keys must have permission `600` and belong to `root:root`.

------------------------------------------------------------------------

## 🔟 kube-apiserver --- Final Working systemd Configuration

Important fixes applied:

-   Added `--bind-address=0.0.0.0`
-   Removed problematic requestheader flags
-   Ensured service-account signing key exists
-   Ensured encryption-config path is correct

``` ini
ExecStart=/usr/local/bin/kube-apiserver \
  --advertise-address=<NODE_PRIVATE_IP> \
  --bind-address=0.0.0.0 \
  --secure-port=6443 \
  --etcd-servers=https://10.0.2.68:2379,https://10.0.2.254:2379,https://10.0.2.5:2379 \
  --etcd-cafile=/etc/kubernetes/pki/ca.pem \
  --etcd-certfile=/etc/kubernetes/pki/etcd-server.pem \
  --etcd-keyfile=/etc/kubernetes/pki/etcd-server-key.pem \
  --authorization-mode=Node,RBAC \
  --client-ca-file=/etc/kubernetes/pki/ca.pem \
  --tls-cert-file=/etc/kubernetes/pki/kube-apiserver.pem \
  --tls-private-key-file=/etc/kubernetes/pki/kube-apiserver-key.pem \
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \
  --service-account-signing-key-file=/etc/kubernetes/pki/ca-key.pem \
  --service-account-key-file=/etc/kubernetes/pki/ca.pem \
  --service-cluster-ip-range=10.32.0.0/24 \
  --enable-admission-plugins=NodeRestriction \
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \
  --v=2
```



## ✅ Current Cluster State

-   etcd cluster running (3 nodes)
-   kube-apiserver running on cp-1 / cp-2 / cp-3
-   NLB routing correctly
-   PKI correctly distributed
-   File permissions secured
-   Control plane networking validated

Cluster is now ready for:

-   kube-controller-manager
-   kube-scheduler
-   Worker node bootstrap

