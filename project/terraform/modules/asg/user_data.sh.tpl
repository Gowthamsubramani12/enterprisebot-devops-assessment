#!/usr/bin/env bash
# =============================================================================
# EC2 User Data — bootstraps application instances on first boot
#
# This script runs as root at instance launch.
# It: installs Docker, authenticates to ECR, pulls the latest image, and
# starts the container as a systemd service for automatic restart on reboot.
# =============================================================================
set -euo pipefail

# Install Docker
dnf update -y
dnf install -y docker awscli
systemctl enable docker
systemctl start docker

# Authenticate to ECR
aws ecr get-login-password --region ${aws_region} \
  | docker login --username AWS --password-stdin ${ecr_repository_url}

# Pull and run the application container
docker pull ${ecr_repository_url}:latest

# Create a systemd unit for the container
cat > /etc/systemd/system/enterprisebot.service <<EOF
[Unit]
Description=EnterpriseBot Application Container
After=docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=5
ExecStartPre=-/usr/bin/docker stop enterprisebot
ExecStartPre=-/usr/bin/docker rm enterprisebot
ExecStart=/usr/bin/docker run \
  --name enterprisebot \
  --rm \
  -p ${app_port}:${app_port} \
  -e APP_NAME=${project_name} \
  ${ecr_repository_url}:latest
ExecStop=/usr/bin/docker stop enterprisebot

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable enterprisebot
systemctl start enterprisebot
