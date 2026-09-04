# ClashX VPN App Store creative handoff

Date: 2026-09-01

## Deliverable

- Storefront: United States, `en-US`
- Platform/device set: iPhone `APP_IPHONE_67` (ASC accepts the 1320×2868 assets in this set)
- Final screenshots: `final/en-US/01-protect-wifi.png`, `02-free-trial.png`, `03-choose-region.png`
- Local promotional hero: `final/en-US/promo-hero-en-US.png` (1600×900; ASC has no generic promotional-hero upload slot, so retain it for the product page/marketing pack)
- Raw simulator capture: `raw/en-US/home-signed.png`

## Narrative and claim ledger

1. Public Wi‑Fi protection in one tap — supported by the Home connection flow and product brief.
2. One-time 10-minute protected-usage allowance — supported by the current `FreeExperienceStore` implementation and ASC Description/Promotional Text; the clock pauses when disconnected.
3. Region selection — supported by the current Locations catalog and Home location card.

No competitor names, prices, rankings, ratings, speed guarantees, permanent-free claims, or unsupported privacy absolutes are used in the creative.

## ASC upload evidence

The three final screenshots were uploaded to version localization `b5b85107-057c-4693-8f8b-2484ebf6c7ce`, screenshot set `72744f83-c915-4036-8602-f29608d40774`, in the order shown above. ASC readback reported `COMPLETE` and `1320×2868` for all three assets.

## Capture limitation

The simulator cannot install a functional Network Extension configuration, so the authentic Home capture reports `VPN unavailable` while still showing the real catalog, region, free-trial card, and Pro CTA. Before App Review submission, replace the first three assets with a real-device capture showing the normal disconnected/protected state, then re-run the same asset-dimension and claim checks. Do not treat the current simulator capture as proof of VPN runtime availability.
