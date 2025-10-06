# BindCaptain Systemd Service Setup

This guide explains how to configure BindCaptain to run automatically at system startup using systemd.

## Overview

BindCaptain can be configured as a systemd service to:
- Start automatically at boot
- Restart automatically if it fails
- Be managed using standard systemctl commands
- Run in the background without manual intervention

## Quick Setup

### 1. Install the Service

#### Automatic Installation (Recommended)
The script will offer to install the systemd service when `run` is executed and the service is not found:

```bash
sudo ./bindcaptain.sh run
```

#### Manual Installation
You can also install the service manually:

```bash
sudo ./bindcaptain.sh install
```

This will:
- Install BindCaptain to `/opt/bindcaptain/`
- Create the systemd service file
- Set up the configuration directory
- Reload systemd daemon

### 2. Configure DNS Settings

Edit your DNS configuration files in `/opt/bindcaptain/config/`:

```bash
sudo nano /opt/bindcaptain/config/named.conf
# Add your zone files and configuration
```

### 3. Enable and Start

Enable the service to start at boot and start it immediately:

```bash
sudo systemctl enable bindcaptain
sudo systemctl start bindcaptain
```

### 4. Verify Installation

Check the service status:

```bash
sudo systemctl status bindcaptain
```

## Service Management Commands

### Basic Service Control

```bash
# Start the service
sudo systemctl start bindcaptain

# Stop the service
sudo systemctl stop bindcaptain

# Restart the service
sudo systemctl restart bindcaptain

# Check service status
sudo systemctl status bindcaptain

# View service logs
sudo journalctl -u bindcaptain -f
```

### Enable/Disable at Boot

```bash
# Enable service to start at boot
sudo systemctl enable bindcaptain

# Disable service from starting at boot
sudo systemctl disable bindcaptain

# Check if service is enabled
systemctl is-enabled bindcaptain
```

### Using BindCaptain Script Commands

The BindCaptain script provides integrated service management commands:

```bash
# Install service (if not already installed)
sudo ./bindcaptain.sh install

# Uninstall service
sudo ./bindcaptain.sh uninstall

# Enable service
sudo ./bindcaptain.sh enable

# Disable service
sudo ./bindcaptain.sh disable

# Start service
sudo ./bindcaptain.sh start

# Stop service
sudo ./bindcaptain.sh stop-service

# Restart service
sudo ./bindcaptain.sh restart

# Show service status
sudo ./bindcaptain.sh service-status
```

## Service Configuration

### Service File Location

The systemd service file is located at:
```
/etc/systemd/system/bindcaptain.service
```

### Environment Variables

The service uses the following environment variables:

- `BINDCAPTAIN_CONFIG_PATH=/opt/bindcaptain/config` - DNS configuration directory
- `TZ=UTC` - Timezone setting

### Service Behavior

- **Type**: `oneshot` with `RemainAfterExit=yes`
- **Restart Policy**: `on-failure` with 10-second delay
- **Timeout**: 60 seconds for start, 30 seconds for stop
- **User**: Runs as root (required for port 53 binding)

## Troubleshooting

### Service Won't Start

1. Check service status:
   ```bash
   sudo systemctl status bindcaptain
   ```

2. View detailed logs:
   ```bash
   sudo journalctl -u bindcaptain -n 50
   ```

3. Check configuration:
   ```bash
   sudo /opt/bindcaptain/bindcaptain.sh validate
   ```

### Container Issues

1. Check container status:
   ```bash
   sudo podman ps -a | grep bindcaptain
   ```

2. View container logs:
   ```bash
   sudo podman logs bindcaptain
   ```

3. Test DNS functionality:
   ```bash
   dig @localhost example.com
   ```

### Port Conflicts

If port 53 is already in use:

1. Check what's using port 53:
   ```bash
   sudo netstat -tulpn | grep :53
   ```

2. Stop conflicting services:
   ```bash
   sudo systemctl stop systemd-resolved
   sudo systemctl disable systemd-resolved
   ```

## Manual Installation

If you prefer to install manually:

### 1. Create Installation Directory

```bash
sudo mkdir -p /opt/bindcaptain
```

### 2. Copy Files

```bash
sudo cp bindcaptain.sh /opt/bindcaptain/
sudo cp bindcaptain.service /etc/systemd/system/
sudo chmod +x /opt/bindcaptain/bindcaptain.sh
```

### 3. Create Config Directory

```bash
sudo mkdir -p /opt/bindcaptain/config
sudo cp config-examples/* /opt/bindcaptain/config/
```

### 4. Reload and Enable

```bash
sudo systemctl daemon-reload
sudo systemctl enable bindcaptain
sudo systemctl start bindcaptain
```

## Uninstallation

To completely remove BindCaptain service:

```bash
# Stop and disable service
sudo systemctl stop bindcaptain
sudo systemctl disable bindcaptain

# Remove service file
sudo rm /etc/systemd/system/bindcaptain.service

# Reload systemd
sudo systemctl daemon-reload

# Remove installation directory (optional)
sudo rm -rf /opt/bindcaptain
```

## Best Practices

1. **Configuration Management**: Keep your DNS configuration in version control
2. **Monitoring**: Set up monitoring for the service and DNS functionality
3. **Backups**: Regularly backup your DNS zone files
4. **Security**: Ensure proper file permissions on configuration files
5. **Logs**: Monitor service logs for any issues

## Integration with Other Services

### Firewall Configuration

Ensure port 53 is open in your firewall:

```bash
# For firewalld
sudo firewall-cmd --permanent --add-port=53/tcp
sudo firewall-cmd --permanent --add-port=53/udp
sudo firewall-cmd --reload

# For iptables
sudo iptables -A INPUT -p tcp --dport 53 -j ACCEPT
sudo iptables -A INPUT -p udp --dport 53 -j ACCEPT
```

### Network Configuration

Update your system's DNS configuration to use BindCaptain:

```bash
# Edit /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
```

## Support

For issues or questions:

1. Check the service logs: `sudo journalctl -u bindcaptain`
2. Validate configuration: `sudo /opt/bindcaptain/bindcaptain.sh validate`
3. Review container logs: `sudo podman logs bindcaptain`
4. Test DNS functionality: `dig @localhost example.com`
