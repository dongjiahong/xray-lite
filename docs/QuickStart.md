# Quick Start Guide

Follow these steps to get your Xray-lite server up and running quickly.

## 1. Installation

Choose the version that fits your needs.

### Standard Edition (Recommended)
Best for most users on any Linux distribution.
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/undead-undead/xray-lite/main/install.sh)
```

### XDP Edition (Advanced)
Requires Linux Kernel 5.4+ and root privileges for kernel-level protection.
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/undead-undead/xray-lite/feature/dynamic-xdp/install.sh)
```

## 2. Configuration

The installer will generate a default `config.json` in the installation directory (`/opt/xray-lite/`).

Key fields to update:
- `clients -> id`: Your UUID.
- `realitySettings -> privateKey`: Your Reality private key (generated during install).
- `realitySettings -> shortIds`: Use the one provided or generate a new 8-16 character hex string.

## 3. Manage the Service

If installed via script:
```bash
systemctl start xray-lite
systemctl status xray-lite
```

Inspect the effective configuration (protocol stack, port, UUID, Reality, XHTTP):
```bash
/opt/xray-lite/manage.sh show     # or simply: xray-lite show
```

Change only the listen port (UUID and keys stay untouched):
```bash
/opt/xray-lite/manage.sh set-port 8443
```

If running manually:
```bash
./vless-server -c config.json
```

## 4. Client Connection

Xray-lite is **asymmetrically compatible**. You can use any standard VLESS client:
- **Android**: v2rayNG, Matsuri
- **iOS**: Shadowrocket, Stash, Streisand
- **Windows/macOS**: v2rayN, Nekoray, Clash-Verge

### Example VLESS Link structure:
`vless://uuid@your_ip:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=your_public_key&sid=your_short_id&type=tcp&encryption=none#Xray-Lite-Server`
