# 📦 JellyfinOfflineCacher

A lightweight offline caching utility for [Jellyfin](https://jellyfin.org/) written in PowerShell.

JellyfinOfflineCacher allows you to subscribe to movies and TV shows from your Jellyfin server, automatically cache offline copies locally, and play them back later using VLC.

The project is designed for:

* Travel/offline viewing
* Low-bandwidth environments

---

# ⚙️ Features

* Interactive terminal UI
* Subscribe to movies and TV shows
* Automatically sync unplayed episodes
* Downloads transcoded MP4 copies from Jellyfin
* VLC playback integration
* Configurable transcoding quality

---

# ✨ How It Works

For TV shows:

* The script checks your watched status in Jellyfin
* Downloads up to 5 unplayed episodes
* Removes old cached episodes automatically

For movies:

* Downloads and stores the full movie offline

Downloaded media is stored locally under:

```text
~/Jellyfin/
```
---

# 📋 Requirements

## Required Software

* PowerShell 7+
* [FFmpeg](https://www.ffmpeg.org)
* [VLC Media Player](https://www.videolan.org/)
* A running Jellyfin server
* A valid Jellyfin API key

## Required PowerShell Module

This project depends on the [JellyfinPS](https://github.com/mikethomp/JellyfinPS) module.

---

# 📥 Installation

Clone the repository:

```bash
git clone https://github.com/mikethomp/JellyfinOfflineCacher.git
```

---

# 🏃 Usage

Basic example:

```powershell
.\JellyfinOfflineCacher.ps1 `
    -JellyfinHost "jellyfin.example.com" `
    -JellyfinUser "john" `
    -ApiKey "YOUR_API_KEY"
```

With specials prioritized first:

```powershell
.\JellyfinOfflineCacher.ps1 `
    -JellyfinHost "jellyfin.example.com" `
    -JellyfinUser "john" `
    -ApiKey "YOUR_API_KEY" `
    -SyncSpecialsFirst
```

---

# Notes

* Old episodes are automatically removed during sync
* ffmpeg must be available in PATH
* VLC must be available in PATH
* Transcoding load occurs on the Jellyfin server

---

# 💡 Future Ideas

Future enhancements:

* Automated syncing
* Track and sync play position
* Mark items as played after watching

---

## 🤝 Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

---

## 🙌 Acknowledgments

* [Jellyfin](https://github.com/jellyfin) — open-source media system powering the API used by this script.
