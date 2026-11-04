# Build notes

The detailed development record is maintained separately from this public repository. Do not commit credentials, signing passwords, local account exports, or device diagnostics.

- `assets/coolapk_auth_blob.b64` is a local-only asset ignored by Git. Provide it locally to enable signed Coolapk API requests; without it, signing reports an explicit missing-material error.
- Android release signing uses the ignored `android/key.properties` and local keystore. Configure these locally before producing a signed release; no signing password is supplied by this repository.
- Run `flutter pub get`, then `flutter test --no-pub` and `dart analyze lib test` for local checks. Build only ARM64 with the command in [README](README.md).
- APKs, build caches, rollback copies, local SDK configuration and internal development records are excluded from source delivery.
