# Development notes

The maintained development record is [GreenNote.md](D:/App/开发文档/GreenNote.md). Keep API coverage, known limits, signing/build checks, and validation results there. Do not duplicate credentials or signing passwords in this repository.

- `assets/coolapk_auth_blob.b64` is a local-only asset and is ignored by Git. Provide it locally to enable signed Coolapk API requests; without it, signing reports an explicit missing-material error.
