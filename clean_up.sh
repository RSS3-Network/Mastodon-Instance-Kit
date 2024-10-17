#!/bin/bash

# Comprehensive cleanup script for Mastodon deployment

# Function to check if a directory exists
dir_exists() {
    if [ -d "$1" ]; then
        return 0
    else
        return 1
    fi
}

# Function to check if a file exists
file_exists() {
    if [ -f "$1" ]; then
        return 0
    else
        return 1
    fi
}

# Change to the Mastodon directory
cd ~/Mastodon-Instance-Kit/mastodon 2>/dev/null || {
    echo "Mastodon directory not found. It may have been already removed or not created."
}

# Stop and remove all Docker containers
echo "Stopping and removing Docker containers..."
sudo docker-compose down --remove-orphans --volumes

# Remove all Docker volumes
echo "Removing Docker volumes..."
sudo docker volume rm $(sudo docker volume ls -q) 2>/dev/null

# Remove all Docker networks
echo "Removing Docker networks..."
sudo docker network prune -f

# Remove all Docker images related to Mastodon
echo "Removing Mastodon-related Docker images..."
sudo docker rmi $(sudo docker images | grep 'tootsuite/mastodon' | awk '{print $3}') 2>/dev/null
sudo docker rmi $(sudo docker images | grep 'ghcr.io/rss3-network/mastodon-instance-kit' | awk '{print $3}') 2>/dev/null

# Remove the Mastodon directory and its contents
echo "Removing Mastodon directory..."
cd ..
sudo rm -rf mastodon

# Remove any created directories
echo "Removing created directories..."
sudo rm -rf /opt/mastodon

# Remove Caddy data
echo "Removing Caddy data..."
sudo rm -rf caddy

# Remove the PostgreSQL data directory
echo "Removing PostgreSQL data..."
sudo rm -rf postgres14

# Remove the Redis data directory
echo "Removing Redis data..."
sudo rm -rf redis

# Remove any log files
echo "Removing log files..."
sudo rm -rf logs

# Remove the tootctl output file if it exists
echo "Removing tootctl output file..."
sudo rm -f tootctl_output.txt

# Remove any environment files
echo "Removing environment files..."
sudo rm -f .env*

# Remove any potential leftover files
echo "Removing any potential leftover files..."
sudo rm -rf ~/Mastodon-Instance-Kit

# Prune Docker system
echo "Pruning Docker system..."
sudo docker system prune -af --volumes

# Check for any remaining Docker resources
if [ "$(sudo docker ps -aq)" ]; then
    echo "Warning: Some Docker containers still exist. You may want to manually remove them."
fi

if [ "$(sudo docker volume ls -q)" ]; then
    echo "Warning: Some Docker volumes still exist. You may want to manually remove them."
fi

if [ "$(sudo docker network ls --format '{{.Name}}' | grep -v 'bridge\|host\|none')" ]; then
    echo "Warning: Some custom Docker networks still exist. You may want to manually remove them."
fi

# Final checks
echo "Performing final checks..."
if dir_exists "/opt/mastodon" || dir_exists "~/Mastodon-Instance-Kit" || dir_exists "postgres14" || dir_exists "redis"; then
    echo "Warning: Some directories still exist. You may want to manually remove them."
fi

if file_exists ".env.production" || file_exists "tootctl_output.txt"; then
    echo "Warning: Some files still exist. You may want to manually remove them."
fi

echo "Cleanup completed. All Mastodon-related data and Docker resources should have been removed."
echo "If you saw any warnings, please address them manually to ensure a complete cleanup."
echo "You can now safely run the deployment script again if needed."
