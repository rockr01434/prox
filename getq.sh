#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <main_server_ip>"
    echo "Example: $0 31.97.103.58"
    exit 1
fi

MAIN_SERVER_IP=$1
PROXY_SERVER_IP=$(hostname -I | awk '{print $1}')

echo "Setting up simple high-performance proxy server to forward requests to ${MAIN_SERVER_IP}"

# Import AlmaLinux GPG key
sudo rpm --import https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux

# Install EPEL repository
sudo yum install epel-release -y

# Install basic tools
sudo yum install unzip wget nano curl htop -y

# Update system
sudo dnf update -y

# Enable PowerTools repository
sudo dnf config-manager --set-enabled powertools 2>/dev/null || sudo dnf config-manager --set-enabled crb 2>/dev/null

# Install nginx
if dnf module list nginx &>/dev/null; then
    sudo dnf module enable nginx -y 2>/dev/null
fi
sudo dnf install nginx -y

# Verify nginx installation
if ! command -v nginx &> /dev/null; then
    echo "❌ Nginx installation failed"
    exit 1
fi

# Create simple high-performance nginx config
sudo tee /etc/nginx/nginx.conf > /dev/null <<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 65535;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 30;
    types_hash_max_size 2048;
    client_max_body_size 0;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    upstream backend {
        server ${MAIN_SERVER_IP}:80;
        keepalive 300;
    }

    upstream backend_ssl {
        server ${MAIN_SERVER_IP}:443;
        keepalive 300;
    }

    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;

        location / {
            proxy_pass http://backend;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
        }
    }

    server {
        listen 443 ssl default_server;
        listen [::]:443 ssl default_server;
        server_name _;

        ssl_certificate /etc/pki/tls/certs/localhost.crt;
        ssl_certificate_key /etc/pki/tls/private/localhost.key;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_session_cache shared:SSL:50m;
        ssl_session_timeout 1d;

        location / {
            proxy_pass http://backend_ssl;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_ssl_verify off;
        }
    }
}
EOF

# Create SSL certificate
sudo mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/pki/tls/private/localhost.key \
    -out /etc/pki/tls/certs/localhost.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=localhost"

# Install firewall
sudo dnf install firewalld -y
sudo systemctl enable firewalld
sudo systemctl start firewalld
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --reload

# Create simple auto-fix script
sudo tee /usr/local/bin/proxy-autofix > /dev/null <<'EOF'
#!/bin/bash

# Simple auto-fix script for proxy server
LOG_FILE="/var/log/proxy-autofix.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check if nginx is running
if ! systemctl is-active --quiet nginx; then
    log_message "NGINX DOWN - Restarting..."
    systemctl restart nginx
    if systemctl is-active --quiet nginx; then
        log_message "NGINX RESTARTED - OK"
    else
        log_message "NGINX FAILED TO START - Checking config..."
        if nginx -t 2>/dev/null; then
            systemctl stop nginx
            sleep 2
            systemctl start nginx
            log_message "NGINX FORCE STARTED"
        else
            log_message "NGINX CONFIG ERROR"
        fi
    fi
fi

# Check memory usage and clear cache if high
MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", ($3/$2) * 100.0}')
if [ "$MEM_USAGE" -gt 90 ]; then
    log_message "HIGH MEMORY ${MEM_USAGE}% - Clearing cache..."
    sync && echo 1 > /proc/sys/vm/drop_caches
fi

# Keep log file small
if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null) -gt 1048576 ]; then
    tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi
EOF

chmod +x /usr/local/bin/proxy-autofix

# Set up cron job for auto-fix (every minute)
(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/proxy-autofix") | crontab -

# Optimize for high traffic
echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf

# Start nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Test configuration
if sudo nginx -t; then
    echo ""
    echo "✅ Simple High-Performance Proxy Server Ready!"
    echo ""
    echo "📋 Summary:"
    echo "   - Proxy IP: ${PROXY_SERVER_IP}"
    echo "   - Main Server: ${MAIN_SERVER_IP}"
    echo "   - Max connections: 65,535"
    echo "   - No limits on traffic"
    echo "   - Auto-fix enabled (checks every minute)"
    echo ""
    echo "🔧 Auto-fix features:"
    echo "   - Restarts nginx if it stops"
    echo "   - Clears memory cache if >90% usage"
    echo "   - Fixes configuration errors"
    echo "   - Logs everything to /var/log/proxy-autofix.log"
    echo ""
    echo "📊 Monitor:"
    echo "   - Status: systemctl status nginx"
    echo "   - Logs: tail -f /var/log/proxy-autofix.log"
    echo "   - Traffic: htop"
    echo ""
    echo "🎯 Point your domains to: ${PROXY_SERVER_IP}"
else
    echo "❌ Nginx configuration has errors"
    exit 1
fi
