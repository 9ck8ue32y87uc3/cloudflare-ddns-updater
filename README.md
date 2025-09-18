# ☁️ Cloudflare DDNS Updater

This is a fork of [K0p1-Git/cloudflare-ddns-updater](https://github.com/K0p1-Git/cloudflare-ddns-updater), enhanced and merged to support both IPv4 and IPv6 updates with Slack & Discord notifications.

A simple Dynamic DNS (DDNS) updater for Cloudflare.  
Automatically updates your A (IPv4) and AAAA (IPv6) records when your public IP changes, with optional Slack and Discord notifications.

---

## 🚀 Features
- Supports both **IPv4** and **IPv6** addresses.
- Automatically detects your public IP using multiple services.
- Updates Cloudflare DNS records when your IP changes.
- Sends notifications to **Slack** or **Discord** when updates succeed or fail.
- Written entirely in **BASH** for simplicity and portability.
- Can run as a **cron job** for automated updates.
