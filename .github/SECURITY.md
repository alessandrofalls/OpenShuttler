# Security Policy

## Supported Versions

We release security updates for the latest minor and patch versions of OpenShuttler:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Security Architecture & Guarantees

OpenShuttler is engineered with security and transparency as core design principles:

1. **Zero External Dependencies:**
   * Built exclusively with standard Apple APIs (`Foundation`, `AppKit`, `OSLog`).
   * No third-party packages, no npm, no Pods, no binary blobs — minimizing software supply chain risks.

2. **Zero Telemetry & 100% Offline:**
   * OpenShuttler does not track, collect, or transmit any analytics, usage metrics, or error reports.
   * The app contains zero network HTTP client libraries. All network operations are conducted exclusively through your system's native `/usr/bin/ssh` client.

3. **Private Key Protection:**
   * OpenShuttler **never** reads, inspects, or caches private cryptographic keys (e.g., `id_rsa`, `id_ed25519`).
   * It strictly forwards file path references (`-i ~/.ssh/key`) directly to OpenSSH.

4. **Strict Command Sanitization:**
   * All host parameters and command strings are strictly quoted and escaped via POSIX standards before being passed to terminal emulators or shell scripts, preventing command injection attacks.

## Reporting a Vulnerability

If you discover a potential security vulnerability in OpenShuttler, please report it responsibly:

* **Email:** Send details to [alessandro@falls.dev](mailto:alessandro@falls.dev) (or open a confidential GitHub Security Advisory).
* Please include:
  * A clear description of the issue.
  * Steps or proof-of-concept to reproduce the behavior.
  * Any potential impact assessment.

We appreciate your effort in responsibly disclosing issues and will respond within 48 hours.

