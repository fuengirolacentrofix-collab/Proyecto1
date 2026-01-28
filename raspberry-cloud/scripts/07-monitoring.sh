#!/bin/bash
###############################################################################
# Raspberry Pi 5 - Sistema de Monitorización
# Prometheus + Grafana + Alertas
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root (sudo)"
   exit 1
fi

log_info "=== Instalación de Sistema de Monitorización ==="

# 1. Instalar Prometheus
log_info "Instalando Prometheus..."
apt update
apt install -y prometheus prometheus-node-exporter

# Configurar Prometheus
cat > /etc/prometheus/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']

  - job_name: 'nginx'
    static_configs:
      - targets: ['localhost:9113']
EOF

systemctl enable prometheus
systemctl restart prometheus
systemctl enable prometheus-node-exporter
systemctl start prometheus-node-exporter

# 2. Instalar nginx-prometheus-exporter
log_info "Instalando nginx exporter..."
wget https://github.com/nginxinc/nginx-prometheus-exporter/releases/download/v0.11.0/nginx-prometheus-exporter_0.11.0_linux_arm64.tar.gz
tar xzf nginx-prometheus-exporter_0.11.0_linux_arm64.tar.gz
mv nginx-prometheus-exporter /usr/local/bin/
rm nginx-prometheus-exporter_0.11.0_linux_arm64.tar.gz

# Configurar nginx para exportar métricas
cat >> /etc/nginx/sites-available/nextcloud << 'EOF'

# Prometheus metrics
server {
    listen 127.0.0.1:8080;
    location /stub_status {
        stub_status on;
        access_log off;
    }
}
EOF

nginx -t && systemctl reload nginx

# Crear servicio para nginx-exporter
cat > /etc/systemd/system/nginx-exporter.service << 'EOF'
[Unit]
Description=Nginx Prometheus Exporter
After=network.target

[Service]
Type=simple
User=prometheus
ExecStart=/usr/local/bin/nginx-prometheus-exporter -nginx.scrape-uri=http://127.0.0.1:8080/stub_status
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nginx-exporter
systemctl start nginx-exporter

# 3. Crear scripts de monitoreo personalizados
cat > /usr/local/bin/system-monitor.sh << 'EOF'
#!/bin/bash

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           MONITORIZACIÓN DEL SISTEMA                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Temperatura
echo "=== Temperatura ==="
TEMP=$(vcgencmd measure_temp | cut -d'=' -f2)
echo "CPU: $TEMP"
echo ""

# CPU y Memoria
echo "=== CPU y Memoria ==="
top -bn1 | head -5
echo ""

# Disco
echo "=== Uso de Disco ==="
df -h | grep -E "Filesystem|/mnt/secure_cloud|/$"
echo ""

# RAID
echo "=== Estado RAID ==="
if [[ -f /proc/mdstat ]]; then
    cat /proc/mdstat | grep -A 2 md0
fi
echo ""

# Red
echo "=== Conexiones de Red ==="
ss -tunap | grep -E "LISTEN|ESTAB" | wc -l
echo "Conexiones activas: $(ss -tunap | grep ESTAB | wc -l)"
echo ""

# Servicios críticos
echo "=== Servicios Críticos ==="
for service in nginx php8.1-fpm mariadb wg-quick@wg0 fail2ban; do
    STATUS=$(systemctl is-active $service)
    if [[ "$STATUS" == "active" ]]; then
        echo "✓ $service: OK"
    else
        echo "✗ $service: FAILED"
    fi
done
echo ""

# Alertas de temperatura
TEMP_NUM=$(echo $TEMP | sed 's/°C//' | sed "s/'//")
if (( $(echo "$TEMP_NUM > 70" | bc -l) )); then
    echo "⚠️  ALERTA: Temperatura alta ($TEMP)"
fi

# Alertas de disco
DISK_USAGE=$(df -h /mnt/secure_cloud | tail -1 | awk '{print $5}' | sed 's/%//')
if [[ $DISK_USAGE -gt 90 ]]; then
    echo "⚠️  ALERTA: Disco casi lleno (${DISK_USAGE}%)"
fi
EOF

chmod +x /usr/local/bin/system-monitor.sh

# 4. Configurar alertas por email (opcional)
log_info "¿Deseas configurar alertas por email? (yes/no): "
read -p "> " SETUP_EMAIL

if [[ "$SETUP_EMAIL" == "yes" ]]; then
    apt install -y mailutils ssmtp
    
    read -p "Email de destino para alertas: " ALERT_EMAIL
    read -p "Servidor SMTP (ej: smtp.gmail.com:587): " SMTP_SERVER
    read -p "Usuario SMTP: " SMTP_USER
    read -sp "Contraseña SMTP: " SMTP_PASS
    echo ""
    
    cat > /etc/ssmtp/ssmtp.conf << EOF
root=${ALERT_EMAIL}
mailhub=${SMTP_SERVER}
AuthUser=${SMTP_USER}
AuthPass=${SMTP_PASS}
UseSTARTTLS=YES
FromLineOverride=YES
EOF
    
    chmod 640 /etc/ssmtp/ssmtp.conf
    
    # Script de alertas
    cat > /usr/local/bin/send-alert.sh << 'EOF'
#!/bin/bash

SUBJECT="$1"
MESSAGE="$2"

echo "$MESSAGE" | mail -s "[Raspberry Cloud] $SUBJECT" root
EOF
    
    chmod +x /usr/local/bin/send-alert.sh
    
    log_info "Alertas por email configuradas"
fi

# 5. Monitoreo de temperatura continuo
cat > /usr/local/bin/temp-monitor.sh << 'EOF'
#!/bin/bash

TEMP=$(vcgencmd measure_temp | cut -d'=' -f2 | sed 's/°C//' | sed "s/'//")
THRESHOLD=75

if (( $(echo "$TEMP > $THRESHOLD" | bc -l) )); then
    logger -t temp-monitor "ALERTA: Temperatura alta: ${TEMP}°C"
    if command -v send-alert.sh &> /dev/null; then
        send-alert.sh "Temperatura Alta" "La temperatura del sistema es ${TEMP}°C (umbral: ${THRESHOLD}°C)"
    fi
fi
EOF

chmod +x /usr/local/bin/temp-monitor.sh

# Ejecutar cada 5 minutos
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/temp-monitor.sh") | crontab -

# 6. Reporte diario del sistema
cat > /usr/local/bin/daily-report.sh << 'EOF'
#!/bin/bash

REPORT="/tmp/daily-report.txt"

{
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         REPORTE DIARIO - $(date +%Y-%m-%d)                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    /usr/local/bin/system-monitor.sh
    echo ""
    /usr/local/bin/security-status.sh
    echo ""
    /usr/local/bin/backup-status.sh
    
} > "$REPORT"

if command -v send-alert.sh &> /dev/null; then
    cat "$REPORT" | mail -s "[Raspberry Cloud] Reporte Diario" root
fi

cat "$REPORT"
EOF

chmod +x /usr/local/bin/daily-report.sh

# Ejecutar diariamente a las 8:00 AM
(crontab -l 2>/dev/null; echo "0 8 * * * /usr/local/bin/daily-report.sh") | crontab -

log_info "=== Sistema de monitorización configurado ==="
echo ""
log_info "COMANDOS ÚTILES:"
log_info "  - Ver estado del sistema: sudo system-monitor.sh"
log_info "  - Reporte completo: sudo daily-report.sh"
log_info "  - Métricas Prometheus: http://localhost:9090"
echo ""
log_info "Monitoreo automático:"
log_info "  - Temperatura: cada 5 minutos"
log_info "  - Reporte diario: 8:00 AM"
