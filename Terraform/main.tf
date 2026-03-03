
# VPC
resource "aws_vpc" "main" {
  cidr_block = "172.16.0.0/16"
  tags = {
    Name = "main-vpc"
    }
}

#Interner Getway
resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main.id
    tags = {
      Name = "main-igw"
    }
  
}

#public Subnet
resource "aws_subnet" "public" {
    vpc_id = aws_vpc.main.id
    cidr_block = "172.16.2.0/24"
    map_public_ip_on_launch = true
    availability_zone = "us-east-1a"
    tags = {
      Name ="public-subnet"
    }
  
}

#private subnet
resource "aws_subnet" "private" {
    vpc_id = aws_vpc.main.id
    cidr_block = "172.16.1.0/24"
    availability_zone = "us-east-1a"
    tags = {
      Name ="private-subnet"
    }
  
}

# Elastic IP For NAT
resource "aws_eip" "nat" {
    depends_on = [ aws_internet_gateway.igw ]
    tags = {
      Name = "nat-eip"
    }
  
}

# NAT Gatway in puplic sub
resource "aws_nat_gateway" "nat" {
    allocation_id = aws_eip.nat.id
    subnet_id = aws_subnet.public.id
    tags = {
      Name = "nat-gatway"
    }
  
}

# Route table for public subnet 
resource "aws_route_table" "public_rt" {
    vpc_id = aws_vpc.main.id
    tags = {
      Name = "public-rt"
    }
  
}

resource "aws_route" "public_internet_access" {
    route_table_id = aws_route_table.public_rt.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  
}
resource "aws_route_table_association" "public_association" {
    subnet_id = aws_subnet.public.id
    route_table_id = aws_route_table.public_rt.id
  
}

# Route table for private subnet 
resource "aws_route_table" "private_rt" {
    vpc_id = aws_vpc.main.id
    tags = {
      Name = "private-rt"
    }
  
}

resource "aws_route" "private_internet_access" {
    route_table_id = aws_route_table.private_rt.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id

    depends_on = [ aws_nat_gateway.nat ]
  
}
resource "aws_route_table_association" "private_association" {
    subnet_id = aws_subnet.private.id
    route_table_id = aws_route_table.private_rt.id
  
}

#Launch EC2 Ins. in Public subnet
resource "aws_instance" "web_server" {
    ami                          = "ami-052064a798f08f0d3"
    instance_type                = "t3.micro"  # Free Tier eligible
    subnet_id                    = aws_subnet.public.id
    vpc_security_group_ids       = [ aws_default_security_group.default.id ]
    associate_public_ip_address  = true 
    key_name                     = "web-server-key"
    
    user_data = <<-EOF
              #!/bin/bash
              # Just basic setup - provisioners will do the rest
              echo "EC2 instance started" > /var/log/user-data.log
              EOF

    tags = {
      Name = "web-server"
    }
    
    # Wait for SSH to be ready
    provisioner "remote-exec" {
      inline = ["echo 'SSH connection established'"]
      
      connection {
        type        = "ssh"
        user        = "ec2-user"
        private_key = file("${path.module}/web-server-key.pem")
        host        = self.public_ip
        timeout     = "5m"
      }
    }
    
    # Install everything via provisioner (faster and controllable)
    provisioner "remote-exec" {
      inline = [
        "echo '📦 Installing Docker and Python...'",
        "sudo dnf update -y",
        "sudo dnf install -y docker python3-pip wget tar stress-ng sysstat",
        "sudo systemctl start docker",
        "sudo systemctl enable docker",
        "sudo usermod -aG docker ec2-user",
        "echo '🐳 Pulling and starting Docker app...'",
        "sudo docker pull abdelatty99/myapp:latest",
        "sudo docker run -d --name myapp --restart always -p 80:8000 abdelatty99/myapp:latest",
        "echo '📊 Installing Node Exporter...'",
        "cd /tmp",
        "wget -q https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz",
        "tar xf node_exporter-1.8.2.linux-amd64.tar.gz",
        "sudo mv node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/",
        "sudo useradd -rs /bin/false node_exporter || true",
        "echo '⚙️  Creating Node Exporter service...'",
        "sudo bash -c 'cat > /etc/systemd/system/node_exporter.service <<NODEEOF\n[Unit]\nDescription=Node Exporter\nAfter=network.target\n\n[Service]\nUser=node_exporter\nExecStart=/usr/local/bin/node_exporter\n\n[Install]\nWantedBy=multi-user.target\nNODEEOF'",
        "sudo systemctl daemon-reload",
        "sudo systemctl start node_exporter",
        "sudo systemctl enable node_exporter",
        "echo '📁 Creating directories...'",
        "sudo mkdir -p /opt/self-heal/{scripts,tests,logs}",
        "sudo chown -R ec2-user:ec2-user /opt/self-heal",
        "sudo chmod -R 755 /opt/self-heal",
        "echo '✅ Setup completed!'"
      ]
      
      connection {
        type        = "ssh"
        user        = "ec2-user"
        private_key = file("${path.module}/web-server-key.pem")
        host        = self.public_ip
      }
    }
    
    # Upload scripts directory
    provisioner "file" {
      source      = "${path.module}/../scripts"
      destination = "/tmp/scripts"
      
      connection {
        type        = "ssh"
        user        = "ec2-user"
        private_key = file("${path.module}/web-server-key.pem")
        host        = self.public_ip
      }
    }
    
    # Upload tests directory
    provisioner "file" {
      source      = "${path.module}/../tests"
      destination = "/tmp/tests"
      
      connection {
        type        = "ssh"
        user        = "ec2-user"
        private_key = file("${path.module}/web-server-key.pem")
        host        = self.public_ip
      }
    }
    
    # Move files and set permissions
    provisioner "remote-exec" {
      inline = [
        "echo '📁 Moving files to /opt/self-heal...'",
        "sudo cp -r /tmp/scripts/* /opt/self-heal/scripts/",
        "sudo cp -r /tmp/tests/* /opt/self-heal/tests/",
        "sudo chmod +x /opt/self-heal/scripts/*.sh",
        "sudo chmod +x /opt/self-heal/tests/*.sh",
        "sudo chown -R ec2-user:ec2-user /opt/self-heal",
        "echo '✅ Self-healing scripts deployed successfully'"
      ]
      
      connection {
        type        = "ssh"
        user        = "ec2-user"
        private_key = file("${path.module}/web-server-key.pem")
        host        = self.public_ip
      }
    }
    
    # Install Python dependencies for webhook receiver
    provisioner "remote-exec" {
      inline = [
        "echo '🐍 Installing Python dependencies...'",
        "pip3 install --user -r /opt/self-heal/scripts/webhook_requirements.txt",
        "echo '✅ Python dependencies installed successfully'"
      ]
      
      connection {
        type        = "ssh"
        user        = "ec2-user"
        private_key = file("${path.module}/web-server-key.pem")
        host        = self.public_ip
      }
    }
    
    # Create systemd service for webhook receiver
    provisioner "remote-exec" {
      inline = [
        "echo '🪝 Setting up Webhook receiver service...'",
        "sudo bash -c 'cat > /etc/systemd/system/webhook-receiver.service <<WEBHOOKEOF\n[Unit]\nDescription=Self-Healing Webhook Receiver\nAfter=network.target\n\n[Service]\nType=simple\nUser=ec2-user\nWorkingDirectory=/opt/self-heal/scripts\nExecStart=/usr/bin/python3 /opt/self-heal/scripts/webhook_receiver.py\nRestart=always\nRestartSec=10\n\n[Install]\nWantedBy=multi-user.target\nWEBHOOKEOF'",
        "sudo systemctl daemon-reload",
        "sudo systemctl start webhook-receiver",
        "sudo systemctl enable webhook-receiver",
        "echo '✅ Webhook receiver service started successfully'"
      ]
      
      connection {
        type        = "ssh"
        user        = "ec2-user"
        private_key = file("${path.module}/web-server-key.pem")
        host        = self.public_ip
      }
    }
  
}

# Deploy Dashboard and Webhook as systemd services
resource "null_resource" "deploy_dashboard" {
  depends_on = [aws_instance.web_server]
  
  triggers = {
    always_run = timestamp()  # Deploy every time
  }

  # Upload dashboard directory
  provisioner "file" {
    source      = "${path.module}/../scripts/dashboard"
    destination = "/tmp/dashboard"
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/web-server-key.pem")
      host        = aws_instance.web_server.public_ip
    }
  }

  # Upload systemd service files
  provisioner "file" {
    source      = "${path.module}/../scripts/dashboard.service"
    destination = "/tmp/dashboard.service"
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/web-server-key.pem")
      host        = aws_instance.web_server.public_ip
    }
  }

  provisioner "file" {
    source      = "${path.module}/../scripts/webhook.service"
    destination = "/tmp/webhook.service"
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/web-server-key.pem")
      host        = aws_instance.web_server.public_ip
    }
  }

  # Install and start services
  provisioner "remote-exec" {
    inline = [
      "echo '🎨 Deploying Self-Healing Dashboard...'",
      
      # Move dashboard to final location
      "sudo rm -rf /opt/self-heal/dashboard",
      "sudo mv /tmp/dashboard /opt/self-heal/dashboard",
      "sudo chown -R ec2-user:ec2-user /opt/self-heal/dashboard",
      
      # Install Flask dependencies
      "echo '📦 Installing Flask dependencies...'",
      "pip3 install --user Flask==3.0.0 Werkzeug==3.0.1",
      
      # Install systemd services
      "echo '⚙️  Installing systemd services...'",
      "sudo mv /tmp/dashboard.service /etc/systemd/system/dashboard.service",
      "sudo mv /tmp/webhook.service /etc/systemd/system/webhook.service",
      
      # Stop old webhook-receiver if exists and start new services
      "sudo systemctl stop webhook-receiver 2>/dev/null || true",
      "sudo systemctl disable webhook-receiver 2>/dev/null || true",
      
      # Reload systemd and start new services
      "sudo systemctl daemon-reload",
      "sudo systemctl enable webhook dashboard",
      "sudo systemctl restart webhook dashboard",
      
      # Wait and verify
      "sleep 5",
      "echo '✅ Verifying services...'",
      "sudo systemctl is-active webhook && echo '✅ Webhook: Running' || echo '❌ Webhook: Failed'",
      "sudo systemctl is-active dashboard && echo '✅ Dashboard: Running' || echo '❌ Dashboard: Failed'",
      
      "echo '✅ Dashboard deployed successfully!'"
    ]
    
    connection {
      type        = "ssh"
      user        = "ec2-user"
      private_key = file("${path.module}/web-server-key.pem")
      host        = aws_instance.web_server.public_ip
    }
  }
}

#use default Security group
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id

  ingress = [
    {
      description      = "Allow SSH"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
    {
      description      = "Allow HTTP"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
    {
      description      = "Allow App Port 8000"
      from_port        = 8000
      to_port          = 8000
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
    {
      description      = "Allow Node Exporter for Prometheus"
      from_port        = 9100
      to_port          = 9100
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]  # للأمان الأفضل: استخدم IP جهازك فقط
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
    {
      description      = "Allow Webhook Receiver for Alertmanager"
      from_port        = 5000
      to_port          = 5000
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]  # للأمان الأفضل: استخدم IP جهازك فقط
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    },
    {
      description      = "Allow Self-Healing Dashboard"
      from_port        = 5001
      to_port          = 5001
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  egress = [
    {
      description      = "Allow all outbound traffic" # ✅ أضفنا الـ description هنا
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups  = []
      self             = false
    }
  ]

  tags = {
    Name = "web-sg"
  }
}

# Update monitoring configuration files with EC2 IP
resource "null_resource" "update_monitoring_configs" {
  depends_on = [null_resource.deploy_dashboard]
  
  triggers = {
    ec2_ip = aws_instance.web_server.public_ip
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "🔧 Updating monitoring configs with EC2 IP..."
      cd ${path.module}/../monitoring
      
      # Update Alertmanager webhook URL
      sed -i.bak "s|url: 'http://[0-9.]*:5000/webhook'|url: 'http://${aws_instance.web_server.public_ip}:5000/webhook'|g" alertmanager.yml
      
      # Update Prometheus targets
      sed -i.bak "s|targets: \\['[0-9.]*:9100'\\]|targets: ['${aws_instance.web_server.public_ip}:9100']|g" prometheus.yml
      
      echo "✅ Monitoring configs updated!"
    EOT
  }
}

output "website_url" {
  value = "http://${aws_instance.web_server.public_ip}"
}

output "public_ip" {
  value = aws_instance.web_server.public_ip
}

output "dashboard_url" {
  description = "Self-Healing Dashboard"
  value       = "http://${aws_instance.web_server.public_ip}:5001"
}

output "all_service_urls" {
  description = "All Service URLs"
  value = {
    patient_web       = "http://${aws_instance.web_server.public_ip}"
    grafana           = "http://${aws_instance.web_server.public_ip}:3000"
    prometheus        = "http://${aws_instance.web_server.public_ip}:9090"
    alertmanager      = "http://${aws_instance.web_server.public_ip}:9093"
    dashboard         = "http://${aws_instance.web_server.public_ip}:5001"
    webhook_receiver  = "http://${aws_instance.web_server.public_ip}:5000"
  }
}
