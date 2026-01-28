#!/bin/bash
###############################################################################
# Raspberry Pi 5 - Configuración WireGuard VPN
# VPN segura para acceso remoto
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

log_info "=== Configuración de WireGuard VPN ==="

# 1. Instalar WireGuard
log_info "Instalando WireGuard..."
apt update
apt install -y wireguard wireguard-tools qrencode

# 2. Habilitar IP forwarding
log_info "Habilitando IP forwarding..."
sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sysctl -p

# 3. Generar claves del servidor
log_info "Generando claves del servidor..."
cd /etc/wireguard
umask 077

wg genkey | tee server_private.key | wg pubkey > server_public.key
SERVER_PRIVATE_KEY=$(cat server_private.key)
SERVER_PUBLIC_KEY=$(cat server_public.key)

# 4. Obtener IP pública
log_info "Detectando IP pública..."
PUBLIC_IP=$(curl -s ifconfig.me)
log_info "IP pública detectada: ${PUBLIC_IP}"

read -p "¿Es correcta esta IP pública? (yes/no): " IP_CORRECT
if [[ "$IP_CORRECT" != "yes" ]]; then
    read -p "Introduce tu IP pública o dominio: " PUBLIC_IP
fi

# 5. Configurar interfaz de red
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
log_info "Interfaz de red detectada: ${INTERFACE}"

# 6. Crear configuración del servidor
log_info "Creando configuración del servidor..."

cat > /etc/wireguard/wg0.conf << EOF
[Interface]
# Configuración del servidor WireGuard
Address = 10.8.0.1/24
ListenPort = 51820
PrivateKey = ${SERVER_PRIVATE_KEY}

# Reglas de firewall
PostUp = ufw route allow in on wg0 out on ${INTERFACE}
PostUp = iptables -t nat -I POSTROUTING -o ${INTERFACE} -j MASQUERADE
PostUp = ip6tables -t nat -I POSTROUTING -o ${INTERFACE} -j MASQUERADE
PreDown = ufw route delete allow in on wg0 out on ${INTERFACE}
PreDown = iptables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE
PreDown = ip6tables -t nat -D POSTROUTING -o ${INTERFACE} -j MASQUERADE

# Clientes (se añadirán con el script add-vpn-client.sh)
EOF

chmod 600 /etc/wireguard/wg0.conf

# 7. Crear script para añadir clientes
cat > /usr/local/bin/add-vpn-client.sh << 'SCRIPT_EOF'
#!/bin/bash

if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ejecutarse como root"
   exit 1
fi

if [[ -z "$1" ]]; then
    echo "Uso: $0 <nombre-cliente>"
    exit 1
fi

CLIENT_NAME="$1"
WG_DIR="/etc/wireguard"
CLIENT_DIR="${WG_DIR}/clients"
mkdir -p "${CLIENT_DIR}"

# Obtener siguiente IP disponible
LAST_IP=$(grep "AllowedIPs" ${WG_DIR}/wg0.conf | tail -1 | cut -d'=' -f2 | cut -d'/' -f1 | xargs)
if [[ -z "$LAST_IP" ]]; then
    NEXT_IP="10.8.0.2"
else
    LAST_OCTET=$(echo $LAST_IP | cut -d'.' -f4)
    NEXT_OCTET=$((LAST_OCTET + 1))
    NEXT_IP="10.8.0.${NEXT_OCTET}"
fi

# Generar claves del cliente
cd "${CLIENT_DIR}"
wg genkey | tee "${CLIENT_NAME}_private.key" | wg pubkey > "${CLIENT_NAME}_public.key"
CLIENT_PRIVATE_KEY=$(cat "${CLIENT_NAME}_private.key")
CLIENT_PUBLIC_KEY=$(cat "${CLIENT_NAME}_public.key")

# Leer clave pública del servidor
SERVER_PUBLIC_KEY=$(cat ${WG_DIR}/server_public.key)
SERVER_ENDPOINT=$(curl -s ifconfig.me)

# Añadir peer al servidor
cat >> ${WG_DIR}/wg0.conf << EOF

# Cliente: ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${NEXT_IP}/32
EOF

# Crear configuración del cliente
cat > "${CLIENT_DIR}/${CLIENT_NAME}.conf" << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${NEXT_IP}/24
DNS = 1.1.1.1, 1.0.0.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${SERVER_ENDPOINT}:51820
AllowedIPs = 10.8.0.0/24, 192.168.0.0/16
PersistentKeepalive = 25
EOF

# Generar código QR para móviles
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Cliente VPN creado: ${CLIENT_NAME}"
echo "║  IP asignada: ${NEXT_IP}"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "Configuración guardada en: ${CLIENT_DIR}/${CLIENT_NAME}.conf"
echo ""
echo "Código QR para móviles:"
qrencode -t ansiutf8 < "${CLIENT_DIR}/${CLIENT_NAME}.conf"
echo ""
echo "Para aplicar cambios: sudo systemctl restart wg-quick@wg0"
SCRIPT_EOF

chmod +x /usr/local/bin/add-vpn-client.sh

# 8. Habilitar y arrancar WireGuard
log_info "Habilitando WireGuard..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# 9. Configurar firewall
log_info "Configurando firewall para WireGuard..."
ufw allow 51820/udp comment 'WireGuard VPN'
ufw reload

# 10. Crear primer cliente de ejemplo
log_info "¿Deseas crear un cliente VPN ahora? (yes/no): "
read -p "> " CREATE_CLIENT

if [[ "$CREATE_CLIENT" == "yes" ]]; then
    read -p "Nombre del cliente (ej: laptop, movil): " CLIENT_NAME
    /usr/local/bin/add-vpn-client.sh "$CLIENT_NAME"
fi

# 11. Crear script de información VPN
cat > /usr/local/bin/vpn-status.sh << 'EOF'
#!/bin/bash

echo "╔════════════════════════════════════════════════════════════╗"
echo "║              ESTADO DE WIREGUARD VPN                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "=== Estado del servicio ==="
systemctl status wg-quick@wg0 --no-pager | head -5
echo ""

echo "=== Configuración de la interfaz ==="
wg show
echo ""

echo "=== Clientes conectados ==="
wg show wg0 peers
echo ""

echo "=== Tráfico ==="
wg show wg0 transfer
echo ""
EOF

chmod +x /usr/local/bin/vpn-status.sh

# 12. Guardar información de configuración
INFO_FILE="/root/wireguard-info.txt"
cat > "$INFO_FILE" << EOF
╔════════════════════════════════════════════════════════════╗
║           INFORMACIÓN DE WIREGUARD VPN                     ║
╚════════════════════════════════════════════════════════════╝

Endpoint público: ${PUBLIC_IP}:51820
Red VPN: 10.8.0.0/24
IP del servidor: 10.8.0.1

Clave pública del servidor: ${SERVER_PUBLIC_KEY}

COMANDOS ÚTILES:
  - Añadir cliente: sudo add-vpn-client.sh <nombre>
  - Ver estado: sudo vpn-status.sh
  - Reiniciar VPN: sudo systemctl restart wg-quick@wg0
  - Ver logs: sudo journalctl -u wg-quick@wg0 -f

CONFIGURACIÓN DE CLIENTES:
  Los archivos de configuración se guardan en: /etc/wireguard/clients/
  
  Para Windows/Linux: Importa el archivo .conf en WireGuard
  Para móviles: Escanea el código QR generado

SEGURIDAD:
  - Puerto 51820/UDP debe estar abierto en tu router (port forwarding)
  - Los clientes solo pueden acceder a la red local (192.168.0.0/16)
  - Split-tunneling configurado (solo tráfico local va por VPN)

IMPORTANTE: Guarda este archivo en un lugar seguro
EOF

chmod 600 "$INFO_FILE"

log_info "=== Configuración de WireGuard completada ==="
echo ""
log_info "Información guardada en: ${INFO_FILE}"
echo ""
log_warn "IMPORTANTE: Configura port forwarding en tu router:"
log_warn "  Puerto: 51820 UDP"
log_warn "  Destino: IP local de esta Raspberry Pi"
echo ""
log_info "Para añadir más clientes: sudo add-vpn-client.sh <nombre>"
log_info "Para ver estado: sudo vpn-status.sh"
