#!/bin/bash

echo "🧹 COMPLETE CLEANUP - Removing all proxy server components..."

# Stop all services first
echo "Stopping services..."
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl stop firewalld 2>/dev/null || true

# Remove nginx completely
echo "Removing nginx..."
sudo systemctl disable nginx 2>/dev/null || true
sudo dnf remove nginx -y 2>/dev/null || true
sudo yum remove nginx -y 2>/dev/null || true

# Remove nginx directories and configs
sudo rm -rf /etc/nginx/
sudo rm -rf /var/log/nginx/
sudo rm -rf /var/cache/nginx/
sudo rm -rf /run/nginx.pid
sudo rm -rf /etc/systemd/system/nginx.service
sudo rm -rf /etc/yum.repos.d/nginx.repo

# Remove certbot
echo "Removing certbot..."
sudo dnf remove certbot python3-certbot-nginx -y 2>/dev/null || true

# Remove firewalld
echo "Removing firewalld..."
sudo systemctl disable firewalld 2>/dev/null || true
sudo dnf remove firewalld -y 2>/dev/null || true

# Remove monitoring tools
echo "Removing monitoring tools..."
sudo dnf remove bc sysstat iotop -y 2>/dev/null || true

# Remove auto-recovery scripts
echo "Removing auto-recovery scripts..."
sudo rm -f /usr/local/bin/nginx-monitor
sudo rm -f /usr/local/bin/system-monitor

# Remove cron jobs
echo "Removing cron jobs..."
crontab -l 2>/dev/null | grep -v nginx-monitor | grep -v system-monitor | grep -v "find /var/log" | crontab - 2>/dev/null || true

# Remove log files
echo "Removing log files..."
sudo rm -f /var/log/nginx-monitor.log*
sudo rm -f /var/log/system-monitor.log*
sudo rm -f /etc/logrotate.d/nginx-custom

# Remove emergency configs
sudo rm -f /etc/nginx/conf.d/emergency-limits.conf

# Remove systemd overrides
sudo rm -rf /etc/systemd/system/nginx.service.d/

# Clean package cache
echo "Cleaning package cache..."
sudo dnf clean all
sudo yum clean all 2>/dev/null || true

# Remove sysctl optimizations (reset to defaults)
echo "Resetting sysctl optimizations..."
sudo cp /etc/sysctl.conf /etc/sysctl.conf.backup 2>/dev/null || true
sudo sed -i '/# Network optimizations for high traffic/,$d' /etc/sysctl.conf

# Reset limits.conf
echo "Resetting file descriptor limits..."
sudo cp /etc/security/limits.conf /etc/security/limits.conf.backup 2>/dev/null || true
sudo sed -i '/\* soft nofile 65535/d' /etc/security/limits.conf
sudo sed -i '/\* hard nofile 65535/d' /etc/security/limits.conf
sudo sed -i '/root soft nofile 65535/d' /etc/security/limits.conf
sudo sed -i '/root hard nofile 65535/d' /etc/security/limits.conf

# Reload systemd
sudo systemctl daemon-reload

# Optional: Remove basic tools (uncomment if you want to test from completely fresh state)
# echo "Removing basic tools..."
# sudo dnf remove unzip wget nano curl htop iftop net-tools bind-utils vim git -y

echo ""
echo "✅ CLEANUP COMPLETED!"
echo ""
echo "🧹 Removed:"
echo "   - Nginx and all configurations"
echo "   - Certbot and SSL tools"
echo "   - Firewalld"
echo "   - Auto-recovery scripts"
echo "   - Cron jobs"
echo "   - Log files"
echo "   - System optimizations"
echo "   - Monitoring tools"
echo ""
echo "🔄 System is now clean and ready for fresh installation!"
echo ""
echo "Run this to test fresh installation:"
echo "curl -fsSL https://raw.githubusercontent.com/rockr01434/prox/main/get.sh | bash -s -- 31.97.103.58"
echo ""
echo "⚠️  Note: Reboot recommended to ensure all changes take effect:"
echo "sudo reboot"
