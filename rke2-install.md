https://docs.rke2.io/install/quickstart   ## Reference link

1. Run the installer
```bash
curl -sfL https://get.rke2.io | sh -
```
This will install the rke2-server service and the rke2 binary onto your machine. Due to its nature, It will fail unless it runs as the root user or through sudo.

2. Enable the rke2-server service
```bash
systemctl enable rke2-server.service
```

3. Start the service
```bash
systemctl start rke2-server.service
```

4. Follow the logs, if you like
```bash
journalctl -u rke2-server -f
```

First, ensure you have access to the kubectl command. RKE2 installs kubectl for you, but you need to add it to your PATH. Run:
```bash
export PATH=$PATH:/var/lib/rancher/rke2/bin
```

RKE2 generates a kubeconfig file that kubectl needs to communicate with the cluster. You need to set the KUBECONFIG environment variable:
```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
```

Now you should be able to run:
```bash
kubectl get nodes
```

After running this installation:

The rke2-server service will be installed. The rke2-server service will be configured to automatically restart after node reboots or if the process crashes or is killed.
Additional utilities will be installed at /var/lib/rancher/rke2/bin/. They include: kubectl, crictl, and ctr. Note that these are not on your path by default.
Two cleanup scripts, rke2-killall.sh and rke2-uninstall.sh, will be installed to the path at:
/usr/local/bin for regular file systems
/opt/rke2/bin for read-only and brtfs file systems
INSTALL_RKE2_TAR_PREFIX/bin if INSTALL_RKE2_TAR_PREFIX is set
A kubeconfig file will be written to /etc/rancher/rke2/rke2.yaml.
A token that can be used to register other server or agent nodes will be created at /var/lib/rancher/rke2/server/node-token



******* Linux Agent (Worker) Node Installation  *********



The steps on this section requires root level access or sudo to work.

1. Run the installer
```bash
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -
```
This will install the rke2-agent service and the rke2 binary onto your machine. Due to its nature, It will fail unless it runs as the root user or through sudo.

2. Enable the rke2-agent service
```bash
systemctl enable rke2-agent.service
```

3. Configure the rke2-agent service
```bash
mkdir -p /etc/rancher/rke2/
vim /etc/rancher/rke2/config.yaml
```

Content for config.yaml:

```bash
server: https://<server>:9345
token: <token from server node>
```
NOTE
The rke2 server process listens on port 9345 for new nodes to register. The Kubernetes API is still served on port 6443, as normal.

4. Start the service
```bash
systemctl start rke2-agent.service
```

Follow the logs, if you like
```bash
journalctl -u rke2-agent -f
```