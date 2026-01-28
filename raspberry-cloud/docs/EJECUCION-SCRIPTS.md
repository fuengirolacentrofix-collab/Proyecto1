# 🚀 Guía Rápida: Cómo Ejecutar los Scripts

## Preparación Inicial (Solo una vez)

### 1. Clonar el Repositorio

```bash
# En tu sistema Ubuntu
git clone https://github.com/fuengirolacentrofix-collab/Proyecto1.git
cd Proyecto1/raspberry-cloud/scripts
```

### 2. Dar Permisos de Ejecución

```bash
# Hacer todos los scripts ejecutables
chmod +x *.sh
```

## 📋 Opción A: Instalación Automática Completa

La forma más fácil es usar el script maestro:

```bash
sudo ./install.sh
```

Este script ejecutará todo en orden y te guiará paso a paso.

> [!WARNING]
> El sistema se reiniciará después del primer paso. Después del reinicio, ejecuta nuevamente el script con `--continue`

## 📋 Opción B: Instalación Manual Paso a Paso

Si prefieres control total, ejecuta cada script en orden:

### Paso 1: Sistema Base
```bash
sudo ./01-os-setup.sh
```
**Después de este paso: REINICIA EL SISTEMA**
```bash
sudo reboot
```

### Paso 2: Configurar Almacenamiento

**Opción 2A - Con RAID1 (2 discos):**
```bash
sudo ./02-raid-encryption.sh
```
Te preguntará qué discos usar (ejemplo: `/dev/sdb` y `/dev/sdc`)

**Opción 2B - Sin RAID (1 disco):**
```bash
sudo ./02-simple-encryption.sh
```
Te preguntará qué disco usar (ejemplo: `/dev/sdb`)

### Paso 3: Seguridad Básica
```bash
sudo ./03-security-hardening.sh
```

### Paso 4: Instalar Nextcloud
```bash
sudo ./04-nextcloud-install.sh
```

### Paso 5: Configurar VPN
```bash
sudo ./05-wireguard-vpn.sh
```

### Paso 6: Sistema de Backups
```bash
sudo ./06-backup-system.sh
```

### Paso 7: Monitorización
```bash
sudo ./07-monitoring.sh
```

## 🔒 Seguridad Avanzada (Opcional)

### SSH con 2FA
```bash
sudo ./09-ssh-2fa.sh
```

### Hardening Avanzado
```bash
sudo ./08-advanced-hardening.sh
```

### Auditoría de Seguridad
```bash
sudo ./10-security-audit.sh
```

## ✅ Verificar que Todo Funciona

### Comprobar Servicios
```bash
# Nextcloud
sudo systemctl status nginx
sudo systemctl status php8.1-fpm
sudo systemctl status mariadb

# VPN
sudo systemctl status wg-quick@wg0

# Firewall
sudo ufw status

# Fail2ban
sudo fail2ban-client status
```

### Acceder a Nextcloud
```bash
# Obtener la IP del sistema
ip addr show

# Abrir en navegador:
# https://TU-IP-AQUI
```

## 🐛 Solución de Problemas Comunes

### "Permission denied"
```bash
# Asegúrate de usar sudo
sudo ./nombre-del-script.sh
```

### "No such file or directory"
```bash
# Verifica que estás en el directorio correcto
pwd
# Debería mostrar: .../raspberry-cloud/scripts

# Si no, navega al directorio
cd ~/Proyecto1/raspberry-cloud/scripts
```

### "Script not executable"
```bash
# Dale permisos de ejecución
chmod +x *.sh
```

### Ver discos disponibles
```bash
# Para saber qué discos usar en RAID/cifrado
lsblk
# o
sudo fdisk -l
```

## 📝 Notas Importantes

1. **Siempre usa `sudo`** - Todos los scripts necesitan permisos de administrador
2. **Lee las preguntas** - Los scripts te pedirán confirmación y datos (contraseñas, discos, etc.)
3. **Guarda las contraseñas** - Anota las contraseñas de cifrado y claves VPN
4. **Tiempo estimado** - La instalación completa tarda 1-2 horas
5. **Conexión a Internet** - Necesaria para descargar paquetes

## 🎯 Resumen Rápido

```bash
# 1. Preparar
git clone https://github.com/fuengirolacentrofix-collab/Proyecto1.git
cd Proyecto1/raspberry-cloud/scripts
chmod +x *.sh

# 2. Ejecutar (opción fácil)
sudo ./install.sh

# O ejecutar manualmente:
sudo ./01-os-setup.sh
sudo reboot
sudo ./02-simple-encryption.sh  # o 02-raid-encryption.sh
sudo ./03-security-hardening.sh
sudo ./04-nextcloud-install.sh
sudo ./05-wireguard-vpn.sh
sudo ./06-backup-system.sh
sudo ./07-monitoring.sh

# 3. Acceder
# https://tu-ip
```

---

**¿Necesitas ayuda?** Revisa los logs en `/var/log/` o consulta la documentación completa en `docs/`
