#!/bin/bash
###############################################################################
# HARDENING AVANZADO - Seguridad Nivel Militar
# Implementa medidas de seguridad extremas basadas en Zero Trust
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_critical() { echo -e "${RED}${BLUE}[CRÍTICO]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root (sudo)"
   exit 1
fi

log_critical "╔════════════════════════════════════════════════════════════╗"
log_critical "║     HARDENING AVANZADO - SEGURIDAD NIVEL MILITAR          ║"
log_critical "║     Implementación de Zero Trust y Defensa en Profundidad ║"
log_critical "╚════════════════════════════════════════════════════════════╝"
echo ""

# ============================================================================
# 1. SELINUX - Mandatory Access Control (Alternativa a AppArmor)
# ============================================================================

log_info "=== Configurando SELinux (Mandatory Access Control) ==="

# Verificar si AppArmor está activo
if systemctl is-active apparmor &>/dev/null; then
    log_warn "AppArmor está activo. ¿Deseas cambiarlo por SELinux? (yes/no)"
    log_warn "SELinux ofrece control más granular pero es más complejo"
    read -p "> " USE_SELINUX
    
    if [[ "$USE_SELINUX" == "yes" ]]; then
        log_info "Instalando SELinux..."
        apt install -y selinux-basics selinux-policy-default auditd
        
        # Deshabilitar AppArmor
        systemctl stop apparmor
        systemctl disable apparmor
        
        # Activar SELinux
        selinux-activate
        
        log_warn "SELinux instalado. Requiere reinicio para activarse"
        log_warn "Después del reinicio, ejecuta: sudo selinux-config-enforcing"
    else
        log_info "Manteniendo AppArmor. Aplicando perfiles estrictos..."
        
        # Forzar perfiles de AppArmor en modo enforce
        aa-enforce /etc/apparmor.d/*
        
        # Crear perfil personalizado para Nextcloud
        cat > /etc/apparmor.d/usr.bin.php-fpm8.2 << 'EOF'
#include <tunables/global>

/usr/sbin/php-fpm8.2 {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/php>
  
  capability setuid,
  capability setgid,
  capability chown,
  capability dac_override,
  
  /etc/php/8.2/** r,
  /usr/lib/php/** mr,
  /var/www/nextcloud/** rw,
  /mnt/secure_cloud/** rw,
  /tmp/** rw,
  /var/log/nginx/** w,
  
  # Denegar acceso a áreas sensibles
  deny /root/** rwx,
  deny /etc/shadow r,
  deny /etc/ssh/** r,
}
EOF
        
        apparmor_parser -r /etc/apparmor.d/usr.bin.php-fpm8.2
        log_info "Perfiles AppArmor reforzados"
    fi
fi

# ============================================================================
# 2. PUERTO KNOCKING - Ocultar SSH completamente
# ============================================================================

log_info "=== Configurando Port Knocking (SSH invisible) ==="

apt install -y knockd

# Generar secuencia aleatoria de puertos
PORT1=$((RANDOM % 10000 + 50000))
PORT2=$((RANDOM % 10000 + 50000))
PORT3=$((RANDOM % 10000 + 50000))

cat > /etc/knockd.conf << EOF
[options]
    UseSyslog

[openSSH]
    sequence    = ${PORT1},${PORT2},${PORT3}
    seq_timeout = 15
    command     = /sbin/iptables -I INPUT -s %IP% -p tcp --dport 22 -j ACCEPT
    tcpflags    = syn

[closeSSH]
    sequence    = ${PORT3},${PORT2},${PORT1}
    seq_timeout = 15
    command     = /sbin/iptables -D INPUT -s %IP% -p tcp --dport 22 -j ACCEPT
    tcpflags    = syn
EOF

# Habilitar knockd
sed -i 's/START_KNOCKD=0/START_KNOCKD=1/' /etc/default/knockd
systemctl enable knockd
systemctl restart knockd

# Bloquear SSH por defecto en UFW
ufw delete allow 22/tcp 2>/dev/null || true
ufw deny 22/tcp

log_critical "╔════════════════════════════════════════════════════════════╗"
log_critical "║  PORT KNOCKING CONFIGURADO                                 ║"
log_critical "║  SSH ahora está INVISIBLE                                  ║"
log_critical "║                                                            ║"
log_critical "║  Secuencia para abrir SSH:                                ║"
log_critical "║  knock <IP> ${PORT1} ${PORT2} ${PORT3}                     ║"
log_critical "║                                                            ║"
log_critical "║  Secuencia para cerrar SSH:                               ║"
log_critical "║  knock <IP> ${PORT3} ${PORT2} ${PORT1}                     ║"
log_critical "║                                                            ║"
log_critical "║  GUARDA ESTA INFORMACIÓN EN LUGAR SEGURO                  ║"
log_critical "╚════════════════════════════════════════════════════════════╝"

# Guardar información
cat > /root/port-knocking-info.txt << EOF
PORT KNOCKING - INFORMACIÓN CRÍTICA

Secuencia para ABRIR SSH:
knock <IP-servidor> ${PORT1} ${PORT2} ${PORT3}

Secuencia para CERRAR SSH:
knock <IP-servidor> ${PORT3} ${PORT2} ${PORT1}

Ejemplo de uso:
1. knock 192.168.1.100 ${PORT1} ${PORT2} ${PORT3}
2. ssh usuario@192.168.1.100
3. knock 192.168.1.100 ${PORT3} ${PORT2} ${PORT1}

Instalar cliente knock en tu PC:
sudo apt install knockd  # Linux
brew install knock       # macOS
EOF

chmod 600 /root/port-knocking-info.txt

# ============================================================================
# 3. SURICATA - IDS/IPS Avanzado (Mejor que Snort)
# ============================================================================

log_info "=== Instalando Suricata IDS/IPS ==="

apt install -y suricata suricata-update

# Actualizar reglas
suricata-update

# Configurar Suricata en modo IPS (inline)
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

cat > /etc/suricata/suricata.yaml << EOF
%YAML 1.1
---

vars:
  address-groups:
    HOME_NET: "[192.168.0.0/16,10.0.0.0/8,172.16.0.0/12]"
    EXTERNAL_NET: "!\\$HOME_NET"

af-packet:
  - interface: ${INTERFACE}
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes

default-rule-path: /var/lib/suricata/rules
rule-files:
  - suricata.rules

outputs:
  - fast:
      enabled: yes
      filename: fast.log
  - eve-log:
      enabled: yes
      filetype: regular
      filename: eve.json
      types:
        - alert
        - http
        - dns
        - tls
        - files
        - ssh

# Modo IPS - Bloquear amenazas automáticamente
action-order:
  - pass
  - drop
  - reject
  - alert
EOF

systemctl enable suricata
systemctl restart suricata

log_info "Suricata IDS/IPS configurado y activo"

# ============================================================================
# 4. OSSEC - Host-based Intrusion Detection System
# ============================================================================

log_info "=== Instalando OSSEC HIDS ==="

# Instalar dependencias
apt install -y build-essential libssl-dev libpcre2-dev zlib1g-dev

# Descargar e instalar OSSEC
cd /tmp
wget https://github.com/ossec/ossec-hids/archive/3.7.0.tar.gz
tar -xzf 3.7.0.tar.gz
cd ossec-hids-3.7.0

# Instalación desatendida
cat > preloaded-vars.conf << EOF
USER_LANGUAGE="en"
USER_NO_STOP="y"
USER_INSTALL_TYPE="local"
USER_DIR="/var/ossec"
USER_ENABLE_SYSCHECK="y"
USER_ENABLE_ROOTCHECK="y"
USER_ENABLE_ACTIVE_RESPONSE="y"
USER_ENABLE_FIREWALL_RESPONSE="y"
EOF

./install.sh

# Configurar OSSEC
cat >> /var/ossec/etc/ossec.conf << 'EOF'
  <syscheck>
    <frequency>7200</frequency>
    <directories check_all="yes">/etc,/usr/bin,/usr/sbin</directories>
    <directories check_all="yes">/var/www/nextcloud</directories>
    <directories check_all="yes">/etc/wireguard</directories>
    <ignore>/etc/mtab</ignore>
    <ignore>/etc/hosts.deny</ignore>
  </syscheck>

  <rootcheck>
    <frequency>7200</frequency>
  </rootcheck>

  <active-response>
    <command>firewall-drop</command>
    <location>local</location>
    <level>6</level>
    <timeout>600</timeout>
  </active-response>
EOF

/var/ossec/bin/ossec-control start

log_info "OSSEC HIDS instalado y activo"

# ============================================================================
# 5. HARDENING EXTREMO DEL KERNEL
# ============================================================================

log_info "=== Aplicando hardening extremo del kernel ==="

cat > /etc/sysctl.d/99-extreme-hardening.conf << 'EOF'
# Protección contra ataques de red
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 3

# Deshabilitar ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# No enviar ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Ignorar ICMP broadcasts
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Protección contra source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log de paquetes sospechosos
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Protección de memoria extrema
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.yama.ptrace_scope = 2

# Protección contra core dumps
kernel.core_uses_pid = 1
fs.suid_dumpable = 0

# Hardening adicional
kernel.kexec_load_disabled = 1
kernel.unprivileged_bpf_disabled = 1
kernel.unprivileged_userns_clone = 0
net.core.bpf_jit_harden = 2

# Protección contra ataques de tiempo
kernel.perf_event_paranoid = 3

# IPv6 hardening
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

sysctl -p /etc/sysctl.d/99-extreme-hardening.conf

# ============================================================================
# 6. RESTRICCIONES DE USUARIO EXTREMAS
# ============================================================================

log_info "=== Configurando restricciones de usuario extremas ==="

# Limitar uso de su
cat > /etc/pam.d/su << 'EOF'
auth       sufficient pam_rootok.so
auth       required   pam_wheel.so use_uid
auth       include    system-auth
account    include    system-auth
password   include    system-auth
session    include    system-auth
session    optional   pam_xauth.so
EOF

# Crear grupo wheel si no existe
groupadd -f wheel

# Timeout automático de sesiones inactivas
cat >> /etc/profile.d/autologout.sh << 'EOF'
TMOUT=900
readonly TMOUT
export TMOUT
EOF

chmod +x /etc/profile.d/autologout.sh

# Limitar procesos por usuario
cat >> /etc/security/limits.conf << 'EOF'

# Límites extremos de seguridad
* soft nproc 100
* hard nproc 200
* soft nofile 1024
* hard nofile 2048
* hard maxlogins 2
EOF

# ============================================================================
# 7. HONEYPOT - Trampa para atacantes
# ============================================================================

log_info "=== Configurando Honeypot ==="

# Crear servicio honeypot SSH falso en puerto 22
apt install -y python3-twisted

cat > /usr/local/bin/ssh-honeypot.py << 'EOF'
#!/usr/bin/env python3
from twisted.conch import avatar, recvline
from twisted.conch.ssh import factory, keys, session
from twisted.cred import portal
from twisted.internet import reactor
import logging

logging.basicConfig(
    filename='/var/log/honeypot.log',
    level=logging.INFO,
    format='%(asctime)s - INTRUSION ATTEMPT - %(message)s'
)

class HoneypotAvatar(avatar.ConchUser):
    def __init__(self, username):
        avatar.ConchUser.__init__(self)
        self.username = username
        self.channelLookup.update({'session': session.SSHSession})

class HoneypotRealm:
    def requestAvatar(self, avatarId, mind, *interfaces):
        logging.warning(f"Login attempt: {avatarId} from {mind.transport.getPeer()}")
        return interfaces[0], HoneypotAvatar(avatarId), lambda: None

def getRSAKeys():
    from Crypto.PublicKey import RSA
    KEY = RSA.generate(2048)
    return keys.Key(KEY)

factory = factory.SSHFactory()
factory.portal = portal.Portal(HoneypotRealm())
factory.publicKeys = {'ssh-rsa': getRSAKeys()}
factory.privateKeys = {'ssh-rsa': getRSAKeys()}

reactor.listenTCP(22, factory)
reactor.run()
EOF

chmod +x /usr/local/bin/ssh-honeypot.py

# Crear servicio systemd para honeypot
cat > /etc/systemd/system/ssh-honeypot.service << 'EOF'
[Unit]
Description=SSH Honeypot
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ssh-honeypot.py
Restart=always
User=nobody

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ssh-honeypot
systemctl start ssh-honeypot

log_info "Honeypot SSH configurado en puerto 22"

# ============================================================================
# 8. GEOBLOCKING - Bloquear países específicos
# ============================================================================

log_info "=== Configurando Geoblocking ==="

apt install -y geoip-bin geoip-database xtables-addons-common

# Actualizar base de datos GeoIP
mkdir -p /usr/share/xt_geoip
/usr/lib/xtables-addons/xt_geoip_dl
/usr/lib/xtables-addons/xt_geoip_build -D /usr/share/xt_geoip *.csv

# Bloquear países de alto riesgo (ejemplo: CN, RU, KP)
log_warn "¿Deseas bloquear países específicos? (yes/no)"
read -p "> " ENABLE_GEOBLOCK

if [[ "$ENABLE_GEOBLOCK" == "yes" ]]; then
    log_info "Países comunes a bloquear: CN (China), RU (Rusia), KP (Corea del Norte)"
    read -p "Introduce códigos de países separados por coma (ej: CN,RU,KP): " COUNTRIES
    
    IFS=',' read -ra COUNTRY_ARRAY <<< "$COUNTRIES"
    for country in "${COUNTRY_ARRAY[@]}"; do
        iptables -I INPUT -m geoip --src-cc "$country" -j DROP
        log_info "Bloqueado: $country"
    done
    
    # Guardar reglas
    iptables-save > /etc/iptables/rules.v4
fi

# ============================================================================
# 9. CANARY TOKENS - Detectar acceso no autorizado
# ============================================================================

log_info "=== Configurando Canary Tokens ==="

# Crear archivos trampa que alertan si son accedidos
cat > /root/.ssh/id_rsa_BACKUP << 'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
CANARY TOKEN - SI VES ESTO, EL SISTEMA HA SIDO COMPROMETIDO
-----END OPENSSH PRIVATE KEY-----
EOF

# Script que monitorea acceso a archivos trampa
cat > /usr/local/bin/canary-monitor.sh << 'EOF'
#!/bin/bash

CANARY_FILES=(
    "/root/.ssh/id_rsa_BACKUP"
    "/root/.bash_history_backup"
    "/etc/shadow.bak"
)

for file in "${CANARY_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        # Verificar si el archivo ha sido accedido recientemente
        ACCESSED=$(find "$file" -amin -5)
        if [[ -n "$ACCESSED" ]]; then
            logger -p auth.crit "ALERTA DE SEGURIDAD: Canary token accedido: $file"
            echo "ALERTA: Posible intrusión detectada - $file accedido" | mail -s "ALERTA DE SEGURIDAD" root
        fi
    fi
done
EOF

chmod +x /usr/local/bin/canary-monitor.sh

# Ejecutar cada 5 minutos
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/canary-monitor.sh") | crontab -

# ============================================================================
# 10. USB GUARD - Protección contra BadUSB
# ============================================================================

log_info "=== Instalando USBGuard ==="

apt install -y usbguard

# Generar política inicial
usbguard generate-policy > /etc/usbguard/rules.conf

# Configurar para bloquear nuevos dispositivos por defecto
sed -i 's/ImplicitPolicyTarget=allow/ImplicitPolicyTarget=block/' /etc/usbguard/usbguard-daemon.conf

systemctl enable usbguard
systemctl start usbguard

log_info "USBGuard configurado - Nuevos dispositivos USB bloqueados por defecto"

# ============================================================================
# RESUMEN FINAL
# ============================================================================

log_critical ""
log_critical "╔════════════════════════════════════════════════════════════╗"
log_critical "║     HARDENING AVANZADO COMPLETADO                          ║"
log_critical "╚════════════════════════════════════════════════════════════╝"
echo ""
log_info "Medidas de seguridad implementadas:"
log_info "  ✓ MAC (SELinux/AppArmor) con perfiles estrictos"
log_info "  ✓ Port Knocking (SSH invisible)"
log_info "  ✓ Suricata IDS/IPS"
log_info "  ✓ OSSEC HIDS"
log_info "  ✓ Hardening extremo del kernel"
log_info "  ✓ Restricciones de usuario extremas"
log_info "  ✓ Honeypot SSH"
log_info "  ✓ Geoblocking"
log_info "  ✓ Canary Tokens"
log_info "  ✓ USBGuard"
echo ""
log_warn "ARCHIVOS CRÍTICOS CREADOS:"
log_warn "  - /root/port-knocking-info.txt (SECUENCIA SSH)"
log_warn "  - /var/log/honeypot.log (Intentos de intrusión)"
log_warn "  - /var/log/suricata/ (Alertas IDS)"
echo ""
log_critical "IMPORTANTE: Guarda /root/port-knocking-info.txt en lugar seguro"
log_critical "Sin la secuencia correcta, NO podrás acceder por SSH"
