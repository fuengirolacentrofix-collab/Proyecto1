# 🚀 Guía de Inicio Rápido

## Instalación en 10 Minutos

### Requisitos Previos
- ✅ Raspberry Pi 5 con Raspberry Pi OS Lite 64-bit instalado
- ✅ 2x Discos duros de 1TB conectados
- ✅ Conexión a Internet
- ✅ Acceso SSH configurado

### Paso 1: Descargar el Proyecto

```bash
cd ~
git clone <tu-repositorio> raspberry-cloud
cd raspberry-cloud/scripts
chmod +x *.sh
```

### Paso 2: Ejecutar Instalación

```bash
# Opción A: Instalación automática completa
sudo ./install.sh

# Opción B: Instalación paso a paso
sudo ./01-os-setup.sh
sudo reboot
# Después del reinicio:
sudo ./02-raid-encryption.sh
sudo ./03-security-hardening.sh
sudo ./04-nextcloud-install.sh
sudo ./05-wireguard-vpn.sh
sudo ./06-backup-system.sh
sudo ./07-monitoring.sh
```

### Paso 3: Configuración Inicial

#### Nextcloud
1. Abre `https://tu-ip-o-dominio`
2. Crea usuario admin
3. Usa credenciales de `/root/nextcloud-credentials.txt`

#### VPN
```bash
# Crear primer cliente
sudo add-vpn-client.sh mi-laptop

# Escanear QR con móvil o copiar archivo .conf
```

#### SSL (Opcional pero Recomendado)
```bash
sudo certbot --nginx -d tu-dominio.com
```

### Paso 4: Configurar Router

**Port Forwarding necesario:**
- Puerto 443 (TCP) → IP de Raspberry Pi
- Puerto 51820 (UDP) → IP de Raspberry Pi

### Paso 5: Verificar

```bash
sudo system-monitor.sh
sudo security-status.sh
sudo vpn-status.sh
```

## ✅ Checklist Post-Instalación

- [ ] Nextcloud accesible vía HTTPS
- [ ] VPN conecta correctamente
- [ ] Backup automático configurado
- [ ] Temperatura < 70°C
- [ ] Todos los servicios activos
- [ ] Guardadas contraseñas en lugar seguro
- [ ] Backup del header LUKS copiado externamente

## 🎯 Primeros Pasos

### Subir Archivos a Nextcloud
1. Accede vía web o app móvil
2. Arrastra archivos
3. Configura sincronización automática

### Conectar desde Fuera de Casa
1. Conecta VPN
2. Accede a Nextcloud normalmente
3. Desconecta VPN al terminar

### Verificar Backups
```bash
sudo backup-status.sh
```

## 📱 Apps Recomendadas

- **Nextcloud**: [Android](https://play.google.com/store/apps/details?id=com.nextcloud.client) | [iOS](https://apps.apple.com/app/nextcloud/id1125420102)
- **WireGuard**: [Android](https://play.google.com/store/apps/details?id=com.wireguard.android) | [iOS](https://apps.apple.com/app/wireguard/id1441195209)

## 🆘 Problemas Comunes

### No puedo acceder a Nextcloud
```bash
# Verificar servicios
sudo systemctl status nginx php8.1-fpm mariadb

# Ver logs
sudo tail -f /var/log/nginx/error.log
```

### VPN no conecta
```bash
# Verificar servicio
sudo systemctl status wg-quick@wg0

# Verificar firewall en router
# Puerto 51820 UDP debe estar abierto
```

### Temperatura alta
```bash
# Verificar
vcgencmd measure_temp

# Solución: Mejorar ventilación, añadir disipador/ventilador
```

## 📚 Documentación Completa

- [README.md](../README.md) - Documentación completa
- [SECURITY.md](SECURITY.md) - Políticas de seguridad
- [MAINTENANCE.md](MAINTENANCE.md) - Guía de mantenimiento

## 🎉 ¡Listo!

Tu nube privada está funcionando. Disfruta de:
- 📁 Almacenamiento privado cifrado
- 🔒 Acceso seguro desde cualquier lugar
- 🔄 Backups automáticos
- 🛡️ Seguridad de nivel empresarial

---

**¿Necesitas ayuda?** Consulta la documentación completa o ejecuta `sudo daily-report.sh`
