# App Store submission pack

This directory is the local, non-secret source for App Store metadata. Live
App Store Connect state must still be queried before any upload.

Current live record (2026-08-04):

- App: `ClashX VPN: Free Fast Privacy` (`6797934807`)
- Bundle ID: `com.astervpn.Aster`
- Version: `1.0` (`fa188c39-d929-455b-ae15-beb4eb12b894`)
- Locales: `en-US`, `zh-Hant`, `zh-Hans`
- Availability: 174 current territories; China mainland (`CHN`) is disabled
  and future territories are not enabled automatically.

The metadata below is a **draft gate**, not permission to upload. Subtitle,
keywords, promotional text, description, screenshots, review notes, and
subscriptions must remain unpublished until the production transport, legal
URLs, signed device build, StoreKit Sandbox, and review environment have passed
the launch checklist in `docs/PROJECT_STATUS.md`.

Validate each locale with the installed `ios-aso-planner` validator. App Store
Connect remains authoritative for its live byte counter.
