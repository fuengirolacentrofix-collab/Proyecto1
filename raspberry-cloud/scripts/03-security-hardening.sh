#!/bin/bash
###############################################################################
# Raspberry Pi 5 - Hardening de Seguridad Avanzado
# Firewall, Fail2ban, SSH hardening
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

log_info "=== Configuración de Seguridad Avanzada ==="

# 1. Configurar UFW (Firewall)
log_info "Configurando firewall UFW..."

# Resetear UFW
ufw --force reset

# Políticas por defecto: denegar todo entrante, permitir saliente
ufw default deny incoming
ufw default allow outgoing

# Permitir SSH (cambiaremos el puerto después)
ufw allow 22/tcp comment 'SSH'

# Permitir HTTP/HTTPS para Nextcloud
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Permitir WireGuard VPN (puerto por defecto)
ufw allow 51820/udp comment 'WireGuard VPN'

# Protección contra port scanning
ufw limit 22/tcp

# Habilitar logging
ufw logging medium

# Habilitar UFW
ufw --force enable

log_info "Firewall configurado y habilitado"

# 2. Hardening de SSH
log_info "Configurando SSH hardening..."

# Backup de configuración original
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d)

# Crear nueva configuración SSH segura
cat > /etc/ssh/sshd_config << 'EOF'
# SSH Hardened Configuration for Raspberry Pi Cloud

# Puerto SSH (cambiar después de configurar)
Port 22

# Protocolo y cifrado
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Algoritmos de cifrado modernos
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Autenticación
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Configuración de login
LoginGraceTime 30
MaxAuthTries 3
MaxSessions 2
MaxStartups 3:50:10

# Restricciones
AllowUsers *@192.168.*.* *@10.*.*.* 
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no

# Banner y logging
Banner /etc/ssh/banner
PrintMotd no
PrintLastLog yes
LogLevel VERBOSE
SyslogFacility AUTH

# Timeouts
ClientAliveInterval 300
ClientAliveCountMax 2
TCPKeepAlive yes

# Otros
Compression no
UseDNS no
PermitUserEnvironment no
StrictModes yes
EOF

# Crear banner SSH
cat > /etc/ssh/banner << 'EOF'
╔════════════════════════════════════════════════════════════╗
║                                                            ║
║              SISTEMA PRIVADO - ACCESO RESTRINGIDO          ║
║                                                            ║
║  Este sistema es de uso privado. El acceso no autorizado  ║
║  está prohibido y será perseguido legalmente.              ║
║                                                            ║
║  Todas las actividades son monitorizadas y registradas.    ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝
EOF

# Generar claves SSH modernas si no existen
if [[ ! -f /etc/ssh/ssh_host_ed25519_key ]]; then
    ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
fi

# Eliminar claves débiles
rm -f /etc/ssh/ssh_host_dsa_key /etc/ssh/ssh_host_dsa_key.pub
rm -f /etc/ssh/ssh_host_ecdsa_key /etc/ssh/ssh_host_ecdsa_key.pub

# Reiniciar SSH
systemctl restart sshd

log_info "SSH hardening completado"
log_warn "IMPORTANTE: Asegúrate de tener configuradas claves SSH antes de cerrar sesión"

# 3. Configurar Fail2ban
log_info "Configurando Fail2ban..."

# Configuración local de Fail2ban
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Ban por 1 hora
bantime = 3600
findtime = 600
maxretry = 3

# Acción: ban + notificación
banaction = ufw
action = %(action_mwl)s

# Ignorar IPs locales
ignoreip = 127.0.0.1/8 ::1 192.168.0.0/16 10.0.0.0/8

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200

[sshd-ddos]
enabled = true
port = ssh
filter = sshd-ddos
logpath = /var/log/auth.log
maxretry = 6
bantime = 3600

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3

[nginx-noscript]
enabled = true
port = http,https
filter = nginx-noscript
logpath = /var/log/nginx/access.log
maxretry = 6

[nginx-badbots]
enabled = true
port = http,https
filter = nginx-badbots
logpath = /var/log/nginx/access.log
maxretry = 2

[nginx-noproxy]
enabled = true
port = http,https
filter = nginx-noproxy
logpath = /var/log/nginx/access.log
maxretry = 2

[recidive]
enabled = true
filter = recidive
logpath = /var/log/fail2ban.log
bantime = 86400
findtime = 86400
maxretry = 3
EOF

# Habilitar y reiniciar Fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

log_info "Fail2ban configurado y activo"

# 4. Configurar límites de login
log_info "Configurando límites de login..."

cat >> /etc/pam.d/common-auth << 'EOF'

# Bloquear cuenta después de 5 intentos fallidos
auth required pam_tally2.so deny=5 unlock_time=900 onerr=fail
EOF

# 5. Crear script de información de seguridad
cat > /usr/local/bin/security-status.sh << 'EOF'
#!/bin/bash

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           ESTADO DE SEGURIDAD DEL SISTEMA                  ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "=== Firewall (UFW) ==="
ufw status numbered
echo ""

echo "=== Fail2ban - IPs Baneadas ==="
fail2ban-client status sshd | grep "Banned IP"
echo ""

echo "=== Últimos intentos de login fallidos ==="
lastb | head -10
echo ""

echo "=== Conexiones SSH activas ==="
who
echo ""

echo "=== Estado del RAID ==="
cat /proc/mdstat
echo ""

echo "=== Espacio en disco cifrado ==="
df -h /mnt/secure_cloud
echo ""

echo "=== Temperatura del sistema ==="
vcgencmd measure_temp
echo ""

echo "=== Procesos escuchando en red ==="
netstat -tulpn | grep LISTEN
echo ""
EOF

chmod +x /usr/local/bin/security-status.sh

log_info "Script de estado de seguridad creado: /usr/local/bin/security-status.sh"

# 6. Configurar rotación de logs
log_info "Configurando rotación de logs..."

cat > /etc/logrotate.d/security << 'EOF'
/var/log/auth.log
/var/log/fail2ban.log
{
    rotate 12
    weekly
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        systemctl reload rsyslog > /dev/null 2>&1 || true
    endscript
}
EOF

# 7. Configurar monitoreo de integridad de archivos con AIDE
log_info "Instalando AIDE para monitoreo de integridad..."
apt install -y aide aide-common

# Configurar AIDE
cat > /etc/aide/aide.conf.d/99_custom << 'EOF'
# Monitorear archivos críticos del sistema
/etc/ssh p+i+n+u+g+s+b+m+c+md5+sha256
/etc/network p+i+n+u+g+s+b+m+c+md5+sha256
/etc/cron.d p+i+n+u+g+s+b+m+c+md5+sha256
/etc/cron.daily p+i+n+u+g+s+b+m+c+md5+sha256
/etc/sudoers p+i+n+u+g+s+b+m+c+md5+sha256
/etc/passwd p+i+n+u+g+s+b+m+c+md5+sha256
/etc/shadow p+i+n+u+g+s+b+m+c+md5+sha256
/usr/local/bin p+i+n+u+g+s+b+m+c+md5+sha256
EOF

log_info "Inicializando base de datos AIDE (esto puede tardar varios minutos)..."
aideinit

# Mover base de datos
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Crear script de verificación diaria
cat > /etc/cron.daily/aide-check << 'EOF'
#!/bin/bash
/usr/bin/aide --check | mail -s "AIDE Report - $(hostname)" root
EOF

chmod +x /etc/cron.daily/aide-check

log_info "AIDE configurado para verificaciones diarias"

# 8. Resumen final
log_info "=== Configuración de seguridad completada ==="
echo ""
log_info "Servicios configurados:"
log_info "  ✓ Firewall UFW activo"
log_info "  ✓ SSH hardening aplicado"
log_info "  ✓ Fail2ban activo"
log_info "  ✓ AIDE (monitoreo de integridad)"
log_info "  ✓ Rotación de logs"
echo ""
log_warn "PRÓXIMOS PASOS IMPORTANTES:"
log_warn "  1. Configura claves SSH para tu usuario"
log_warn "  2. Verifica que puedes conectarte con clave SSH"
log_warn "  3. Considera cambiar el puerto SSH (edita /etc/ssh/sshd_config)"
log_warn "  4. Ejecuta: security-status.sh para ver el estado"
echo ""
log_info "Para ver el estado de seguridad: sudo security-status.sh"
