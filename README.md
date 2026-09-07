# 🧰 Mint FieldKit

> **A lightweight, repeatable Linux Mint workstation for network technicians, structured cabling professionals, and IT field service.**

Mint FieldKit transforms a standard **Linux Mint 22.3 or 23 MATE or Cinnamon** installation into a practical, lean, field-ready workstation. It is designed around the realities of working on customer sites: limited storage, unfamiliar networks, offline work, equipment diagnostics, documentation, and the need to get useful tools running quickly.

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
- 🗄️ Provide ZFS administration, snapshots, and replication tools
- 📐 Create network diagrams, floor plans, and rack layouts
- ☁️ Synchronize field documentation with Nextcloud
- 🎵 Add an optional Music flavor for audio work
- 🧪 Preview changes safely with dry-run mode
- 📦 Keep the package catalog separate from the installer logic
- 🖥️ Support both Linux Mint MATE and Cinnamon flavors

---

## 🖥️ Compatibility

| Linux Mint | Desktop | Status |
|---|---|---|
| 22.3 | MATE / Cinnamon | **SUPPORTED / TESTED** |
| 23.x | MATE / Cinnamon | **SUPPORTED / TESTING** |
| Other versions | Any | **NOT SUPPORTED** |

Mint 23 is based on Ubuntu 26.04. FieldKit therefore treats Mint 23 as a compatibility target while continuing to validate external vendor packages and storage tooling against the new Ubuntu base.

In particular, Mint 23 testing includes Tailscale's Ubuntu `resolute` repository, ZFS tooling, Sanoid/Syncoid, CHIRP dependencies, draw.io, and Nextcloud Desktop. WiFiman remains skipped when its stable vendor package is incompatible with the Ubuntu base.

---

## 🖥️ Desktop Flavors

FieldKit uses one common installer engine with a shared core package catalog. Flavor-specific catalogs can add specialized applications without putting them on every workstation.

### MATE

The original FieldKit flavor, optimized for the project's constrained-hardware roots and especially suitable for low-storage systems.

```bash
./scripts/fieldkit-install.sh --dry-run
```

### Cinnamon

The Cinnamon flavor provides the same field toolkit while explicitly validating that the workstation is running Linux Mint Cinnamon.

```bash
./scripts/fieldkit-install-cinnamon.sh --dry-run
```

The Cinnamon launcher delegates to the common installer, so package recommendations and installer behavior remain consistent between flavors.

### Music flavor

The Music flavor adds audio-production and audio-troubleshooting applications without making them part of the lean field-tech baseline.

The recommended Music flavor includes:

- **Audacity** — audio recording, editing, cleanup, and conversion
- **FFmpeg** — command-line media conversion and processing
- **Easy Effects** — PipeWire audio effects and processing
- **PulseAudio Volume Control (`pavucontrol`)** — detailed audio routing and device control

Optional Music applications include **Ardour** and **Carla** for more advanced recording, mixing, routing, and plugin workflows.

Enable the Music flavor with:

```bash
./scripts/fieldkit-install.sh --music --dry-run
```

It can be combined with the Cinnamon launcher:

```bash
./scripts/fieldkit-install-cinnamon.sh --music --dry-run
```

The Music flavor package catalog is maintained separately in:

```text
config/music-packages.conf
```

This keeps audio applications out of the standard FieldKit recommendations while allowing the same workstation to be deployed for both technical and music-oriented work.

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
- 🎙️ Technicians who also need a practical audio workstation

---

## 🧰 Field Toolkit

### 🌐 Networking & Diagnostics

FieldKit's recommended networking toolkit includes:

- **Nmap** — network discovery, port scanning, and service identification
- **WiFiman** — Wi-Fi analysis, speed testing, discovery, and UniFi diagnostics when a compatible vendor package is available
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

### 💾 Storage, ZFS & Replication

FieldKit's storage toolkit includes:

- **smartmontools** — SMART health and storage diagnostics
- **ncdu** — interactive disk-usage analysis
- **duf** — filesystem and storage overview
- **lsof** — open-file, process, and socket diagnostics
- **NTFS support** — read/write support for external NTFS media
- **ZFS tools (`zfsutils-linux`)** — pools, datasets, snapshots, and ZFS administration
- **Sanoid** — automated ZFS snapshot policies and retention
- **Syncoid** — ZFS snapshot replication over local or SSH connections

Sanoid and Syncoid are provided by the Ubuntu/Debian `sanoid` package and are treated as one recommended FieldKit package.

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

### 🎵 Music & Audio

The optional Music flavor provides a practical audio toolkit without bloating the standard field installation.

**Audacity** is the primary Music flavor application for recording, editing, cleanup, and basic production. FFmpeg provides broad media conversion capabilities, while Easy Effects and `pavucontrol` provide useful PipeWire/audio-routing diagnostics and processing.

For users who need a full digital audio workstation, Ardour and Carla are available as optional selections.

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

or for Cinnamon:

```bash
./scripts/fieldkit-install-cinnamon.sh --dry-run
```

For the Music flavor:

```bash
./scripts/fieldkit-install.sh --music --dry-run
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

Core recommendations are maintained in:

```text
config/packages.conf
```

Music flavor recommendations are maintained separately in:

```text
config/music-packages.conf
```

The installer reads these catalogs rather than maintaining a large hard-coded package list.

The catalogs support different application sources, including:

- `apt` — standard Mint/Ubuntu packages
- `external:tailscale` — Tailscale
- `external:ubiquiti` — Ubiquiti WiFiman
- `external:drawio` — draw.io Desktop
- `external:nextcloud` — Nextcloud Desktop Client
- `external:chirp` — CHIRP

Flavor-specific packages are only loaded when the corresponding flavor is enabled. The standard MATE and Cinnamon field deployments therefore remain lean.

---

## 🚀 Installation

Clone the repository and run the appropriate flavor.

### MATE

```bash
git clone https://github.com/Dayagiym/fieldKit.git
cd fieldKit
chmod +x scripts/fieldkit-install.sh
./scripts/fieldkit-install.sh
```

### Cinnamon

```bash
git clone https://github.com/Dayagiym/fieldKit.git
cd fieldKit
chmod +x scripts/fieldkit-install-cinnamon.sh
./scripts/fieldkit-install-cinnamon.sh
```

### Music flavor

The Music flavor can be added to either desktop environment:

```bash
./scripts/fieldkit-install.sh --music
```

or:

```bash
./scripts/fieldkit-install-cinnamon.sh --music
```

For a first pass, use dry-run mode.

> **Tip:** FieldKit is designed to be run as a normal user. It requests elevated privileges only for operations that require them.

---

## 🧱 Design Philosophy

### 🪶 Keep It Lean

Every installed package should earn its place. FieldKit is particularly useful on systems with limited eMMC or SSD storage.

### 🔁 Keep It Reproducible

A fresh Mint installation should be transformable into a predictable working environment every time.

### 🛠️ Keep It Maintainable

The package catalogs are separated from installer logic so applications can be added or removed without rewriting the entire script. Desktop flavors share the same installer engine while specialized flavors can maintain their own package sets.

### 🎯 Keep It Practical

FieldKit favors tools that solve actual problems encountered in networking, structured cabling, infrastructure, IT service, and selected specialty workflows.

### 📴 Keep It Field-Ready

Not every job site has reliable Internet access. Wherever practical, FieldKit favors tools that remain useful offline and do not depend on cloud services for basic functionality.

---

## 🗺️ Project Roadmap

Future development may include:

- 📦 Additional role-based package profiles
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

The project now also supports Cinnamon and is being prepared for Mint 23 while retaining those lightweight constraints as part of FieldKit's design goals.

---

## ❤️ Project Philosophy

A technician's computer should be treated like any other professional tool:

> **Reliable. Organized. Predictable. Ready when the job starts.**

FieldKit exists to make getting there repeatable.

---

## 📄 License

See the repository for current licensing information.
