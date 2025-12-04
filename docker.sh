#!/usr/bin/env bash

set -e  # Exit immediately if a command exits with a non-zero status

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

echo "=== Removing residual Docker files ==="
sudo dnf autoremove -y
sudo rm -rf /var/lib/docker
sudo rm -rf /var/lib/containerd
sudo rm -rf /etc/docker
sudo rm -rf /run/docker.sock
sudo rm -rf /var/run/docker.sock
sudo groupdel docker || true  # ignore error if group doesn't exist
rm -rf ~/.docker

echo "=== Installing Docker dependencies and repo ==="
sudo dnf -y install dnf-plugins-core
sudo dnf-3 config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo -y

echo "=== Installing Docker packages ==="
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "=== Enabling and starting Docker service ==="
sudo systemctl enable --now docker

echo "=== Starting Docker Compose services ==="
sudo docker compose up -d

echo "=== Docker reinstall complete ==="
