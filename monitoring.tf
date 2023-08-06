
provider "aws" {
    access_key = "YOUR ACCESS KEY"
    secret_key = "YOUR SECRET KEY"

    region = "eu-central-1"
}

resource "aws_security_group" "prom" {
    name        = "Prometheus"
    description = "Prom"

    # Allow incoming traffic on port 9090 for Prometheus
    ingress {
        from_port   = 9090
        to_port     = 9090
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Allow incoming traffic on port 3000 for Grafana
    ingress {
        from_port   = 3000
        to_port     = 3000
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # Allow incoming traffic on port 9100 for node-exporter
    ingress {
        from_port   = 9100
        to_port     = 9100
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
       from_port    = 22
       to_port      = 22
       protocol     = "tcp"
       cidr_blocks  = ["0.0.0.0/0"]
    }
    # Allow all outgoing traffic
    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_instance" "Prom" {
    ami           = "ami-04e601abe3e1a910f"
    instance_type = "t2.micro"
    vpc_security_group_ids = [aws_security_group.prom.id]

    user_data = <<-EOF
#!/bin/bash
# Update package lists and install required packages
sudo apt-get update -y
sudo apt-get install -y ca-certificates curl gnupg software-properties-common

#################################

sudo apt-get -y install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg




##################

echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null



# Update package lists again to include the Docker repository
sudo apt-get update -y

# Install Docker and Docker Compose
sudo apt-get install -y docker.io docker-compose


# Create directories for Prometheus and Grafana data persistence
sudo mkdir -p /prometheus

# Create Docker Compose file
cat << 'EOT' | sudo tee /docker-compose.yml
version: '3.8'

networks:
  monitoring:
    driver: bridge

volumes:
  prometheus_data: {}
  grafana_data: {}

services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.rootfs=/rootfs'
      - '--path.sysfs=/host/sys'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
    ports:
      - 9100:9100
    networks:
      - monitoring

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    volumes:
      - /prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    ports:
      - 9090:9090
    networks:
      - monitoring

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    volumes:
      - grafana_data:/var/lib/grafana
    ports:
      - 3000:3000
    networks:
      - monitoring
EOT

# Create Prometheus configuration file
cat << 'EOT' | sudo tee /prometheus.yml
global:
  scrape_interval: 1m

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 1m
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
EOT

# Start Docker Compose
sudo docker-compose up -d

EOF
}
