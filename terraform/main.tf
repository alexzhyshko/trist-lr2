terraform {
  backend "s3" {
    bucket       = "trist-lr2"
    key          = "trist/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "my_ip" {
  type    = string
  default = "79.110.128.209/32"
}

resource "aws_security_group" "web" {
  name = "web-sg"

  tags = {
    Name = "web-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh_from_my_ip" {
  security_group_id = aws_security_group.web.id
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = var.my_ip
}

resource "aws_vpc_security_group_ingress_rule" "http_from_anywhere" {
  security_group_id = aws_security_group.web.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.web.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

variable "dockerhub_user" {
  type      = string
  sensitive = true
}

variable "dockerhub_token" {
  type      = string
  sensitive = true
}

variable "key_name" {
  type    = string
  default = "trist-lr1"
}

data "aws_ssm_parameter" "ubuntu_ami" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.ubuntu_ami.value
  instance_type          = "t3.micro"
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
    #!/bin/bash
    set -eux
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    usermod -aG docker ubuntu
    apt-get install -y git
    git clone https://github.com/alexzhyshko/trist-lr2 /opt/trist-lr2
    cd /opt/trist-lr2
    set +x
    echo "${var.dockerhub_token}" | sudo -u ubuntu -H docker login -u "${var.dockerhub_user}" --password-stdin
    set -x
    docker compose up -d
    echo "Provisioning has finished"
  EOF

  tags = {
    Name = "web"
  }
}

output "public_ip" {
  value = aws_instance.web.public_ip
}
