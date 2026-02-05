#!/bin/bash

# Configuration

FORCE=0

if ! command -v docker &> /dev/null || [ $FORCE -eq 1 ]
then
    info "Uninstalling old versions (if present).."
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove $pkg || true; done
    info "Getting docker. Note: you may see a warning from the docker script, you can safely ignore it"
    sleep 5
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh ./get-docker.sh
    rm get-docker.sh
    sudo usermod -aG docker $USER
else
    echo "Seems like Docker is already installed, skipping."
fi