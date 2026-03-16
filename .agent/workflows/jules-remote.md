---
description: Start a Jules remote session for SubI
---
1. Run `jules remote list --repo` to verify connection (optional).
2. Start session using the SubI repo:
   ```powershell
   jules remote new --repo MrLongNight/SubI --session "<Task Description>"
   ```
   *Note: Always specify `--repo MrLongNight/SubI` as the local directory detection might fail.*
