#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <main_server_ip>"
    echo "Example: $0 31.97.103.58"
    exit 1
fi

MAIN_SERVER_IP=$1
PROXY_SERVER_IP=$(hostname -I | awk '{print $1}')

sudo rpm --import https://repo.almalinux.org/almalinux/RPM-GPG-KEY-AlmaLinux
sudo yum install epel-release -y
sudo yum install unzip wget nano curl -y

if dnf module list nginx &>/dev/null; then
    sudo dnf module enable nginx -y 2>/dev/null
fi
sudo dnf install nginx -y

if ! command -v nginx &> /dev/null; then
    echo "❌ Nginx installation failed"
    exit 1
fi

sudo tee /etc/nginx/nginx.conf > /dev/null <<EOF
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 8192;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server {
        listen 80 default_server;
        listen [::]:80 default_server;
        server_name _;

        location / {
            proxy_pass http://${MAIN_SERVER_IP};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header X-Forwarded-Host \$host;
            proxy_set_header X-Forwarded-Port \$server_port;
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
    }

    server {
        listen 443 ssl default_server;
        listen [::]:443 ssl default_server;
        server_name _;

        ssl_certificate /etc/pki/tls/certs/localhost.crt;
        ssl_certificate_key /etc/pki/tls/private/localhost.key;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            proxy_pass https://${MAIN_SERVER_IP};
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_ssl_verify off;
            proxy_ssl_session_reuse on;
        }
    }
}
EOF

sudo mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/pki/tls/private/localhost.key \
    -out /etc/pki/tls/certs/localhost.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=localhost"

sudo setsebool -P httpd_can_network_connect 1 2>/dev/null || true
sudo setsebool -P httpd_can_network_relay 1 2>/dev/null || true
sudo setenforce 0 2>/dev/null || true
sudo setenforce 1 2>/dev/null || true

sudo tee /usr/local/bin/proxy-autofix > /dev/null <<'EOF'
#!/bin/bash

LOG_FILE="/var/log/proxy-autofix.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

if ! systemctl is-active --quiet nginx; then
    log_message "NGINX DOWN - Restarting..."
    systemctl restart nginx
    if systemctl is-active --quiet nginx; then
        log_message "NGINX RESTARTED - OK"
    else
        log_message "NGINX FAILED TO START"
        systemctl stop nginx
        sleep 2
        systemctl start nginx
    fi
fi

MEM_USAGE=$(free | grep Mem | awk '{printf "%.0f", ($3/$2) * 100.0}')
if [ "$MEM_USAGE" -gt 90 ]; then
    log_message "HIGH MEMORY ${MEM_USAGE}% - Clearing cache..."
    sync && echo 1 > /proc/sys/vm/drop_caches
fi

if [ -f "$LOG_FILE" ] && [ $(stat -c%s "$LOG_FILE" 2>/dev/null) -gt 1048576 ]; then
    tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi
EOF

chmod +x /usr/local/bin/proxy-autofix

(crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/proxy-autofix") | crontab -

echo "* soft nofile 65535" >> /etc/security/limits.conf
echo "* hard nofile 65535" >> /etc/security/limits.conf

sudo nginx -t 2>/dev/null || true

sudo systemctl enable nginx 2>/dev/null || true
sudo systemctl start nginx 2>/dev/null || true

sudo setsebool -P httpd_can_network_connect 1 2>/dev/null || true
sudo setsebool -P httpd_can_network_relay 1 2>/dev/null || true

sudo systemctl restart nginx 2>/dev/null || true

sudo setsebool -P httpd_can_network_connect 1 2>/dev/null || true
sudo setsebool -P httpd_can_network_relay 1 2>/dev/null || true
sudo systemctl restart nginx 2>/dev/null || true

echo "✅ Proxy Ready: ${PROXY_SERVER_IP} → ${MAIN_SERVER_IP}"
