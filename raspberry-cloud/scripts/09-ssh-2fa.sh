#!/bin/bash
###############################################################################
# 2FA para SSH - Autenticación de Dos Factores
# Implementa Google Authenticator para acceso SSH
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

log_info "=== Configurando 2FA para SSH ==="

# Instalar Google Authenticator
apt install -y libpam-google-authenticator qrencode

# Configurar PAM para SSH
log_info "Configurando PAM..."

# Backup de configuración PAM
cp /etc/pam.d/sshd /etc/pam.d/sshd.backup

# Añadir Google Authenticator a PAM
if ! grep -q "pam_google_authenticator.so" /etc/pam.d/sshd; then
    cat >> /etc/pam.d/sshd << 'EOF'

# Google Authenticator 2FA
auth required pam_google_authenticator.so nullok
auth required pam_permit.so
EOF
fi

# Configurar SSH para usar 2FA
log_info "Configurando SSH..."

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.2fa.backup

# Habilitar ChallengeResponseAuthentication
sed -i 's/^ChallengeResponseAuthentication no/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#ChallengeResponseAuthentication yes/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config

# Añadir configuración de autenticación
if ! grep -q "AuthenticationMethods" /etc/ssh/sshd_config; then
    cat >> /etc/ssh/sshd_config << 'EOF'

# 2FA Configuration
AuthenticationMethods publickey,keyboard-interactive
EOF
fi

# Reiniciar SSH
systemctl restart sshd

log_info "2FA configurado en SSH"

# Script para configurar 2FA por usuario
cat > /usr/local/bin/setup-user-2fa.sh << 'EOF'
#!/bin/bash

if [[ $EUID -eq 0 ]]; then
   echo "No ejecutes este script como root"
   echo "Ejecuta como el usuario que necesita 2FA"
   exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║     Configuración de 2FA para $(whoami)"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

google-authenticator -t -d -f -r 3 -R 30 -w 3

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  2FA CONFIGURADO                                           ║"
echo "║  Escanea el código QR con Google Authenticator             ║"
echo "║  Guarda los códigos de emergencia en lugar seguro         ║"
echo "╚════════════════════════════════════════════════════════════╝"
EOF

chmod +x /usr/local/bin/setup-user-2fa.sh

log_warn "╔════════════════════════════════════════════════════════════╗"
log_warn "║  2FA INSTALADO                                             ║"
log_warn "║                                                            ║"
log_warn "║  Cada usuario debe ejecutar:                              ║"
log_warn "║  setup-user-2fa.sh                                        ║"
log_warn "║                                                            ║"
log_warn "║  IMPORTANTE: Configura 2FA ANTES de cerrar sesión         ║"
log_warn "╚════════════════════════════════════════════════════════════╝"
