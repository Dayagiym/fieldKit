# 🧰 Mint FieldKit

> **A lightweight, repeatable Linux Mint MATE workstation for network technicians, structured cabling professionals, and IT field service.**

Mint FieldKit transforms a standard **Linux Mint 22.3 MATE** installation into a practical, lean, field-ready workstation. It is designed around the realities of working on customer sites: limited storage, unfamiliar networks, offline work, equipment diagnostics, documentation, and the need to get useful tools running quickly.

---

## 🎯 What FieldKit Does

FieldKit is more than a package removal script. It is a deployment framework for turning a fresh Mint installation into a consistent technician workstation.

It can:

- 🧹 Remove unnecessary desktop applications
- 🔧 Install a curated field-service toolkit
- 🌐 Provide network discovery and troubleshooting utilities
- 📡 Support Wi-Fi and UniFi diagnostics
- 🔐 Provide secure remote-access tools
- 💾 Diagnose storage and hardware
- 📐 Create network diagrams, floor plans, and rack layouts
- ☁️ Synchronize field documentation with Nextcloud
- 🧪 Preview changes safely with dry-run mode
- 📦 Keep the package catalog separate from the installer logic

---

## 👷 Intended Users

FieldKit is designed for people who work with real infrastructure, including:

- 🔌 Structured cabling technicians
- 🌐 Network installers and engineers
- 📡 UniFi and wireless technicians
- 🧵 Fiber optic technicians
- 🖥️ IT support and field-service technicians
- 🗄️ Server and systems administrators
- 🛠️ Hardware technicians

---

## 🧰 Field Toolkit

### 🌐 Networking & Diagnostics

FieldKit's recommended networking toolkit includes:

- **Nmap** — network discovery, port scanning, and service identification
- **WiFiman** — Wi-Fi analysis, speed testing, discovery, and UniFi diagnostics
- **iperf3** — bandwidth and network performance testing
- **MTR** — live path analysis combining ping and traceroute
- **tcpdump** — packet capture and analysis
- **ethtool** — Ethernet interface and link diagnostics
- **DNS utilities** — `dig` and DNS troubleshooting
- **traceroute** — routing-path diagnostics
- **OpenSSH** — remote administration
- **rsync** — efficient file synchronization

### 🔐 Remote Access

**Tailscale** provides secure mesh-VPN connectivity without requiring SSH or VNC services to be exposed directly to the Internet.

This makes it particularly useful when a technician needs to reach a FieldKit workstation remotely from another trusted system.

### 📐 Diagrams & Documentation

**draw.io Desktop** provides an offline-capable workspace for:

- Network topology diagrams
- Structured-cabling documentation
- Floor plans
- Rack layouts
- Equipment maps
- Field sketches

### ☁️ Nextcloud

The **Nextcloud Desktop Client** is intended for synchronizing job documentation, diagrams, photos, configuration files, reports, and other field data with a technician's Nextcloud server.

---

## 💻 System & Hardware Utilities

FieldKit includes or recommends lightweight tools for diagnosing the workstation itself:

- `htop` / `btop` — resource monitoring
- `lshw` — hardware inventory
- `smartmontools` — storage health and SMART diagnostics
- `pciutils` — PCI hardware identification
- `usbutils` — USB hardware identification
- `jq` — command-line JSON processing
- `curl` / `wget` — HTTP/HTTPS utilities
- `git` — configuration and deployment management

---

## 🧹 Desktop Cleanup

FieldKit deliberately removes software that has little value on a dedicated field workstation when those applications are installed.

Typical recommended removals include:

- Thunderbird
- Hypnotix
- Celluloid
- Rhythmbox
- Drawing
- Pix
- Transmission
- Web App Manager
- GNOME Calendar
- GIMP
- Inkscape

Useful applications such as **Warpinator, Xed, and Xreader** are retained because they have practical field value.

---

## 🧪 Dry-Run Mode

FieldKit supports a safe preview mode:

```bash
./scripts/fieldkit-install.sh --dry-run
```

Dry-run mode shows what FieldKit would remove or install without changing the system.

The interactive menus allow the technician to choose:

- `r` — recommended selections
- `a` — all available selections
- `n` — none
- Individual package numbers

This makes FieldKit useful both as an automated deployment tool and as an interactive technician utility.

---

## 📦 Package Catalog

Package recommendations are maintained in:

```text
config/packages.conf
```

The installer reads the catalog rather than maintaining a large hard-coded package list.

The catalog supports different application sources, including:

- `apt` — standard Mint/Ubuntu packages
- `external:tailscale` — Tailscale
- `external:ubiquiti` — Ubiquiti WiFiman
- `external:drawio` — draw.io Desktop
- `external:nextcloud` — Nextcloud Desktop Client

This separation is intended to make FieldKit easier to maintain and extend.

---

## 🚀 Installation

Clone the repository and run the installer:

```bash
git clone https://github.com/Dayagiym/fieldKit.git
cd fieldKit
chmod +x scripts/fieldkit-install.sh
./scripts/fieldkit-install.sh
```

For a first pass, use dry-run mode:

```bash
./scripts/fieldkit-install.sh --dry-run
```

> **Tip:** FieldKit is designed to be run as a normal user. It requests elevated privileges only for operations that require them.

---

## 🧱 Design Philosophy

### 🪶 Keep It Lean

Every installed package should earn its place. FieldKit is particularly useful on systems with limited eMMC or SSD storage.

### 🔁 Keep It Reproducible

A fresh Mint installation should be transformable into a predictable working environment every time.

### 🛠️ Keep It Maintainable

The package catalog is separated from installer logic so applications can be added or removed without rewriting the entire script.

### 🎯 Keep It Practical

FieldKit favors tools that solve actual problems encountered in networking, structured cabling, infrastructure, and IT service work.

### 📴 Keep It Field-Ready

Not every job site has reliable Internet access. Wherever practical, FieldKit favors tools that remain useful offline and do not depend on cloud services for basic functionality.

---

## 🗺️ Project Roadmap

Future development may include:

- 📦 Role-based package profiles
- 🧾 Automated system and hardware reports
- ⌨️ Field-oriented shell aliases and commands
- 🔄 Recovery and backup utilities
- 💿 Cubic-based custom Mint ISO creation
- 🧪 Automated deployment testing
- 📚 Expanded deployment and maintenance documentation

---

## 🖥️ Original Target Hardware

FieldKit was originally developed around a **Lenovo Chromebook 14e** converted from ChromeOS to Linux Mint using the **MrChromebox firmware utility**, targeting a particularly constrained environment:

- **Linux Mint 22.3 MATE**
- **4 GB RAM**
- **32 GB storage**

That constraint is part of the project's DNA. FieldKit is intended to remain useful even when the hardware is modest and storage is scarce.

---

## ❤️ Project Philosophy

A technician's computer should be treated like any other professional tool:

> **Reliable. Organized. Predictable. Ready when the job starts.**

FieldKit exists to make getting there repeatable.

---

## 📄 License

See the repository for current licensing information.
