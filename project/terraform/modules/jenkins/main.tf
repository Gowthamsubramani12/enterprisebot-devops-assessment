# =============================================================================
# Jenkins EC2 Instance
#
# Interview note:
#   Jenkins runs on a dedicated instance in a PUBLIC subnet (so CI can reach
#   GitHub webhooks) but is protected by a Security Group that restricts
#   access to port 8080 and SSH to a known CIDR.
#   It uses an IAM Instance Profile — never static credentials.
# =============================================================================

resource "aws_instance" "jenkins" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.public_subnet_id
  vpc_security_group_ids = [var.jenkins_sg_id]
  iam_instance_profile   = var.iam_instance_profile_name

  user_data = base64encode(<<-EOF
    #!/usr/bin/env bash
    set -euo pipefail

    # Install Java 17, Docker, and wget
    dnf update -y
    dnf install -y java-17-amazon-corretto docker wget

    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # Install Jenkins LTS
    wget -O /etc/yum.repos.d/jenkins.repo \
      https://pkg.jenkins.io/redhat-stable/jenkins.repo
    rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
    dnf install -y jenkins

    systemctl enable jenkins
    systemctl start jenkins

    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl && mv kubectl /usr/local/bin/

    # Install Helm
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # Install AWS CLI v2
    dnf install -y awscli
  EOF
  )

  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins"
    Role = "cicd"
  }
}

# Elastic IP so the Jenkins URL stays stable across reboots
resource "aws_eip" "jenkins" {
  instance = aws_instance.jenkins.id
  domain   = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-jenkins-eip"
  }
}
