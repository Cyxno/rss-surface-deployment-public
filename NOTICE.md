# NOTICE

RSS — Surface Deployment Stick — Copyright (C) 2026 Cyxno

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, version 3 of the License only (AGPL-3.0-only).

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU Affero General Public License for more details
(see [LICENSE](LICENSE)).

- Original author / copyright holder: **Cyxno (2026)**
- Original repository: <https://github.com/Cyxno/rss-surface-deployment-public>

## Third-party components

The repository deliberately contains **no third-party binaries or source code**;
the components below are downloaded at build/deployment time from their official
sources via `config/sources.json` and `tools/Update-RSSMedia.ps1` and remain
subject to their own licenses and terms — they are **not** relicensed by this
project:

- **Microsoft Windows 11** (image, ADK/WinPE) — proprietary, Microsoft License
  Terms. "Microsoft", "Surface" and "Windows" are trademarks of Microsoft
  Corporation; RSS is not a Microsoft product.
- **Microsoft Surface driver packages (MSI)** — proprietary, Microsoft License
  Terms.
- **wimlib** — GPL-3.0, copyright its respective authors; used unmodified from
  the official binary distribution.

RSS wipes disks: using it implies the user is authorized and informed.
