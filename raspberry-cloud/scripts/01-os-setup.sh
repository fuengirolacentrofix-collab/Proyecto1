#!/bin/bash
###############################################################################
# Raspberry Pi 5 - Sistema Operativo Base Hardened
# Instalación y configuración segura del sistema base
###############################################################################

set -euo pipefail

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Verificar que se ejecuta como root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script debe ejecutarse como root (sudo)"
   exit 1
fi

log_info "=== Iniciando configuración del sistema base ==="

# 1. Actualizar sistema
log_info "Actualizando sistema..."
apt update && apt upgrade -y
apt full-upgrade -y

# 2. Instalar paquetes esenciales de seguridad
log_info "Instalando paquetes de seguridad..."
apt install -y \
    ufw \
    fail2ban \
    unattended-upgrades \
    apt-listchanges \
    needrestart \
    rkhunter \
    lynis \
    auditd \
    apparmor \
    apparmor-utils \
    libpam-tmpdir \
    libpam-pwquality \
    git \
    curl \
    wget \
    htop \
    vim \
    tmux

# 3. Configurar actualizaciones automáticas de seguridad
log_info "Configurando actualizaciones automáticas..."
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# 4. Hardening del kernel (sysctl)
log_info "Aplicando hardening del kernel..."
cat > /etc/sysctl.d/99-security-hardening.conf << 'EOF'
# Protección contra IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Deshabilitar IP forwarding (se habilitará solo para VPN)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Protección contra SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

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

# Ignorar ICMP ping
net.ipv4.icmp_echo_ignore_all = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignorar paquetes ICMP bogus
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Protección contra source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0

# Log de paquetes sospechosos
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Protección de memoria
kernel.randomize_va_space = 2
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1

# Protección contra core dumps
kernel.core_uses_pid = 1
fs.suid_dumpable = 0

# Aumentar rango de puertos efímeros
net.ipv4.ip_local_port_range = 32768 60999

# Optimizaciones TCP
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
EOF

sysctl -p /etc/sysctl.d/99-security-hardening.conf

# 5. Configurar límites de recursos
log_info "Configurando límites de recursos..."
cat >> /etc/security/limits.conf << 'EOF'

# Límites de seguridad
* soft core 0
* hard core 0
* soft nproc 512
* hard nproc 1024
* soft nofile 4096
* hard nofile 8192
EOF

# 6. Deshabilitar servicios innecesarios
log_info "Deshabilitando servicios innecesarios..."
SERVICES_TO_DISABLE=(
    "bluetooth.service"
    "avahi-daemon.service"
    "triggerhappy.service"
)

for service in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-enabled "$service" 2>/dev/null; then
        systemctl disable "$service"
        systemctl stop "$service"
        log_info "Deshabilitado: $service"
    fi
done

# 7. Configurar AppArmor
log_info "Habilitando AppArmor..."
systemctl enable apparmor
systemctl start apparmor

# 8. Configurar auditd
log_info "Configurando auditd..."
systemctl enable auditd
systemctl start auditd

# Reglas de auditoría básicas
cat > /etc/audit/rules.d/hardening.rules << 'EOF'
# Auditar cambios en configuración de red
-w /etc/network/ -p wa -k network_modifications
-w /etc/hosts -p wa -k network_modifications
-w /etc/hostname -p wa -k network_modifications

# Auditar cambios en usuarios y grupos
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/gshadow -p wa -k identity

# Auditar cambios en sudoers
-w /etc/sudoers -p wa -k sudoers_changes
-w /etc/sudoers.d/ -p wa -k sudoers_changes

# Auditar intentos de login
-w /var/log/faillog -p wa -k login_attempts
-w /var/log/lastlog -p wa -k login_attempts
-w /var/run/utmp -p wa -k session
-w /var/log/wtmp -p wa -k session
-w /var/log/btmp -p wa -k session

# Auditar cambios en cron
-w /etc/cron.allow -p wa -k cron
-w /etc/cron.deny -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /etc/cron.daily/ -p wa -k cron
-w /etc/cron.hourly/ -p wa -k cron
-w /etc/cron.monthly/ -p wa -k cron
-w /etc/cron.weekly/ -p wa -k cron
-w /etc/crontab -p wa -k cron

# Auditar cambios en módulos del kernel
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules
EOF

augenrules --load

# 9. Configurar password policy
log_info "Configurando política de contraseñas..."
cat > /etc/security/pwquality.conf << 'EOF'
# Longitud mínima
minlen = 14

# Complejidad
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1

# Máximo de caracteres repetidos
maxrepeat = 3

# Verificar contra diccionario
dictcheck = 1
EOF

# 10. Configurar SSH (preparación para hardening posterior)
log_info "Preparando configuración SSH..."
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# 11. Configurar timezone
log_info "Configurando timezone a Europe/Madrid..."
timedatectl set-timezone Europe/Madrid

# 12. Optimizaciones para Raspberry Pi 5
log_info "Aplicando optimizaciones para Raspberry Pi 5..."

# Habilitar overlayfs para /tmp
echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,noexec,mode=1777,size=512M 0 0" >> /etc/fstab

# 13. Limpiar paquetes innecesarios
log_info "Limpiando sistema..."
apt autoremove -y
apt autoclean -y

# 14. Crear usuario de sistema para servicios
log_info "Creando usuario de sistema para servicios cloud..."
if ! id -u clouduser &>/dev/null; then
    useradd -r -s /bin/false -d /var/lib/clouduser -m clouduser
    log_info "Usuario clouduser creado"
fi

log_info "=== Configuración del sistema base completada ==="
log_info "IMPORTANTE: Reinicia el sistema para aplicar todos los cambios"
log_info "Ejecuta 'sudo reboot' cuando estés listo"
