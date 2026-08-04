# WewPagram mod patch

This repo does **not** contain the full Telegram-iOS source (submodules like
webrtc/tdlib/rlottie are too large to vendor here). Instead:

- `wewpagram-mod/` — our changed/added files, mirroring the real repo's paths
- `wewpagram-config/` — build configuration (api_id/api_hash/bundle_id)
- `.github/workflows/build.yml` — CI that clones upstream Telegram-iOS with
  full submodules, copies `wewpagram-mod/` on top, and builds via Bazel.

Trigger a build manually from the Actions tab, or push to `main`.
