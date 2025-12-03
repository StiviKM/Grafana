#!/usr/bin/env bash

echo "=== Removing Docker packages ==="
sudo dnf remove -y docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-engine \
    docker-ce \
    docker-ce-cli \
    docker-buildx-plugin \
    docker-compose-plugin \
    containerd.io \
    runc

    
sudo dnf autoremove -y
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /etc/docker
sudo rm -rf /run/docker.sock
sudo rm -rf /var/run/docker.sock
sudo groupdel docker
rm -rf ~/.docker
echo "=== Complete ==="
