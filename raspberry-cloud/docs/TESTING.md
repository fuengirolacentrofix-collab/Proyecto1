# Guía de Pruebas en Entornos de Desarrollo

## 🧪 Probar el Sistema sin Raspberry Pi

Este sistema puede probarse en cualquier entorno Linux antes de desplegarlo en la Raspberry Pi 5.

## 💻 Opción 1: Máquina Virtual (Recomendado)

### VirtualBox - Configuración Completa

**Requisitos:**
- VirtualBox instalado
- Ubuntu Server 22.04 LTS ISO
- 4GB RAM disponible
- 30GB espacio en disco

**Pasos:**

1. **Crear VM**
   ```
   Nombre: RaspberryCloudTest
   Tipo: Linux
   Versión: Ubuntu (64-bit)
   RAM: 4096 MB
   Disco 1: 20 GB (sistema)
   Disco 2: 10 GB (datos - opcional para RAID)
   Disco 3: 10 GB (datos - opcional para RAID)
   Red: Bridge Adapter (o NAT con port forwarding)
   ```

2. **Instalar Ubuntu Server**
   - Instalación mínima
   - Habilitar SSH
   - Crear usuario

3. **Configurar Red (si usas NAT)**
   ```
   Port Forwarding:
   - SSH: Host 2222 → Guest 22
   - HTTPS: Host 8443 → Guest 443
   - VPN: Host 51820 → Guest 51820 (UDP)
   ```

4. **Instalar Sistema**
   ```bash
   # Conectar por SSH
   ssh -p 2222 usuario@localhost
   
   # Clonar proyecto
   git clone <tu-repo> raspberry-cloud
   cd raspberry-cloud/scripts
   chmod +x *.sh
   
   # Opción A: Con RAID (si creaste 2 discos virtuales)
   sudo ./01-os-setup.sh
   sudo reboot
   sudo ./02-raid-encryption.sh  # Usa /dev/sdb y /dev/sdc
   
   # Opción B: Sin RAID (un solo disco)
   sudo ./01-os-setup.sh
   sudo reboot
   sudo ./02-simple-encryption.sh  # Usa /dev/sdb
   
   # Continuar con el resto
   sudo ./03-security-hardening.sh
   sudo ./04-nextcloud-install.sh
   sudo ./05-wireguard-vpn.sh
   sudo ./06-backup-system.sh
   sudo ./07-monitoring.sh
   ```

5. **Acceder a Nextcloud**
   - Si usas Bridge: `https://ip-de-la-vm`
   - Si usas NAT: `https://localhost:8443`

### VMware Workstation/Fusion

Similar a VirtualBox, pero con mejor rendimiento:
- Mismo proceso de instalación
- Mejor soporte para nested virtualization
- Más estable para pruebas prolongadas

### QEMU/KVM (Linux Host)

```bash
# Crear VM con virt-manager o:
virt-install \
  --name raspberry-cloud-test \
  --ram 4096 \
  --disk path=/var/lib/libvirt/images/cloud-system.qcow2,size=20 \
  --disk path=/var/lib/libvirt/images/cloud-data1.qcow2,size=10 \
  --disk path=/var/lib/libvirt/images/cloud-data2.qcow2,size=10 \
  --vcpus 2 \
  --os-variant ubuntu22.04 \
  --network bridge=virbr0 \
  --graphics none \
  --console pty,target_type=serial \
  --location 'http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/' \
  --extra-args 'console=ttyS0,115200n8 serial'
```

## 🐳 Opción 2: Docker (Pruebas Parciales)

**Limitaciones:** No se puede probar RAID, cifrado de disco, ni kernel hardening.

**Útil para probar:** Nextcloud, configuraciones de Nginx, PHP, MariaDB.

```dockerfile
# Dockerfile para pruebas
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    nginx \
    mariadb-server \
    php8.1-fpm \
    php8.1-mysql \
    # ... resto de dependencias

# Copiar scripts de configuración
COPY scripts/04-nextcloud-install.sh /tmp/

# Ejecutar instalación
RUN bash /tmp/04-nextcloud-install.sh
```

## 🪟 Opción 3: WSL2 en Windows

**Limitaciones:** 
- ❌ No soporta RAID
- ❌ WireGuard requiere configuración especial
- ✅ Puede probar Nextcloud, backups, scripts básicos

```powershell
# Instalar WSL2
wsl --install -d Ubuntu-22.04

# Dentro de WSL
cd ~
git clone <tu-repo> raspberry-cloud
cd raspberry-cloud/scripts

# Probar scripts individuales (sin RAID ni VPN)
sudo ./01-os-setup.sh  # Algunas funciones no aplicarán
sudo ./04-nextcloud-install.sh
```

## 🖥️ Opción 4: PC/Laptop con Linux

Si tienes un PC viejo o laptop con Linux:

```bash
# Instalar Ubuntu/Debian
# Clonar proyecto
git clone <tu-repo> raspberry-cloud
cd raspberry-cloud/scripts

# Ejecutar instalación completa
sudo ./install.sh

# O paso a paso según tus necesidades
```

**Ventajas:**
- Prueba real en hardware físico
- Todos los features funcionan
- Puedes usar discos USB para RAID

## 🔧 Scripts de Prueba Simplificados

### Probar Solo Nextcloud (Sin RAID, Sin VPN)

```bash
# 1. Sistema base
sudo ./01-os-setup.sh
sudo reboot

# 2. Crear directorio simple (sin cifrado)
sudo mkdir -p /mnt/secure_cloud/nextcloud-data
sudo chown -R www-data:www-data /mnt/secure_cloud

# 3. Seguridad básica
sudo ./03-security-hardening.sh

# 4. Nextcloud
sudo ./04-nextcloud-install.sh

# 5. Acceder
# https://ip-del-servidor
```

### Probar Solo VPN

```bash
# 1. Sistema base
sudo ./01-os-setup.sh
sudo reboot

# 2. VPN
sudo ./05-wireguard-vpn.sh

# 3. Crear cliente
sudo add-vpn-client.sh test-client

# 4. Probar conexión
```

## 📊 Verificación de Funcionalidad

### Checklist de Pruebas

```markdown
## Pruebas Básicas
- [ ] Sistema arranca correctamente
- [ ] Servicios se inician automáticamente
- [ ] Firewall está activo
- [ ] SSH funciona con claves

## Pruebas de Nextcloud
- [ ] Acceso web funciona
- [ ] Login funciona
- [ ] Subir archivo funciona
- [ ] Descargar archivo funciona
- [ ] App móvil conecta

## Pruebas de VPN
- [ ] Servidor VPN arranca
- [ ] Cliente puede conectar
- [ ] Tráfico pasa por VPN
- [ ] Acceso a recursos internos funciona

## Pruebas de Seguridad
- [ ] Fail2ban está activo
- [ ] SSH rechaza passwords
- [ ] Firewall bloquea puertos no autorizados
- [ ] AIDE detecta cambios

## Pruebas de Backups
- [ ] Backup manual funciona
- [ ] Restauración funciona
- [ ] Backup automático se ejecuta
- [ ] Verificación de integridad pasa

## Pruebas de Monitoreo
- [ ] Scripts de monitoreo funcionan
- [ ] Prometheus recopila métricas
- [ ] Alertas se generan correctamente
```

## 🐛 Problemas Comunes en Pruebas

### VM: "No se encuentra el disco"
```bash
# Verificar discos disponibles
lsblk

# Los discos en VM suelen ser /dev/sdb, /dev/sdc
# No /dev/sda (ese es el sistema)
```

### WSL: "systemctl no funciona"
```bash
# WSL2 no usa systemd por defecto
# Solución: Usar servicios manualmente o habilitar systemd
sudo nano /etc/wsl.conf
# Añadir:
# [boot]
# systemd=true
```

### Docker: "No puedo usar LUKS"
```bash
# Docker no soporta cifrado de disco
# Usa volúmenes normales para pruebas
docker volume create nextcloud-data
```

### VirtualBox: "Red no funciona"
```bash
# Cambiar adaptador de red
# Settings → Network → Adapter 1
# Cambiar de NAT a Bridge Adapter
# O configurar Port Forwarding en NAT
```

## 📝 Notas para Pruebas

1. **Snapshots:** Crea snapshots de la VM antes de cada paso importante
2. **Logs:** Guarda logs de cada instalación para debugging
3. **Recursos:** La VM necesita al menos 2GB RAM para Nextcloud
4. **Tiempo:** Primera instalación puede tardar 30-60 minutos
5. **Red:** Asegúrate de que la VM tiene acceso a Internet

## 🚀 Después de Probar

Una vez que hayas probado y todo funcione:

1. **Documenta cambios** necesarios para tu entorno
2. **Ajusta scripts** si es necesario
3. **Crea snapshot** de la VM funcionando
4. **Transfiere** a Raspberry Pi 5 con confianza

---

**Recomendación:** Prueba primero en VirtualBox con la configuración completa (RAID + VPN + todo). Es la forma más cercana al entorno real de Raspberry Pi.
