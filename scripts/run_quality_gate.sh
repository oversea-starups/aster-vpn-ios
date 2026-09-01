#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
destination_id="${ASTER_TEST_DESTINATION_ID:-}"
output_root="${ASTER_QA_OUTPUT_DIR:-$repository_root/build/quality-gate}"
expected_unit_tests=50
expected_ui_tests=9
expected_total_tests=$((expected_unit_tests + expected_ui_tests))

if [[ -z "$destination_id" ]]; then
  echo "error: ASTER_TEST_DESTINATION_ID must identify a healthy arm64 iOS Simulator."
  exit 2
fi

run_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_directory="$output_root/$run_stamp"
result_bundle="$run_directory/Aster.xcresult"
summary_file="$run_directory/test-summary.json"
mkdir -p "$run_directory"

cd "$repository_root"

./setup.sh
./scripts/test_release_configuration.sh

for plist in \
  Aster/Resources/Info.plist \
  Aster/Resources/PrivacyInfo.xcprivacy \
  Aster/Config/Aster.entitlements \
  Aster/Config/PacketTunnel.entitlements
do
  plutil -lint "$plist"
done

if rg -n -i \
  '\b(TODO|FIXME|mock|placeholder|coming soon|not implemented|lorem ipsum)\b' \
  Aster/Sources Aster/Resources \
  --glob '*.swift' \
  --glob '*.plist' \
  --glob '*.xcprivacy' \
  --glob '*.xcstrings' \
  --glob '*.strings'
then
  echo "error: unfinished or test-only marker found in a shipping source."
  exit 1
fi

actual_unit_tests="$(rg -n '^\s*func test[A-Z_a-z0-9]*\(' Aster/Tests/AsterTests | wc -l | tr -d ' ')"
actual_ui_tests="$(rg -n '^\s*func test[A-Z_a-z0-9]*\(' Aster/Tests/AsterUITests | wc -l | tr -d ' ')"
if [[ "$actual_unit_tests" -ne "$expected_unit_tests" || "$actual_ui_tests" -ne "$expected_ui_tests" ]]; then
  echo "error: XCTest inventory changed; expected $expected_unit_tests unit and $expected_ui_tests UI, found $actual_unit_tests unit and $actual_ui_tests UI."
  exit 1
fi

(
  cd Backend/AdMobSSV
  npm run check
  npm test
  npm audit --omit=dev --registry=https://registry.npmjs.org
)

set -o pipefail
xcodebuild test \
  -project Aster.xcodeproj \
  -scheme Aster \
  -destination "platform=iOS Simulator,id=$destination_id" \
  -resultBundlePath "$result_bundle" \
  CODE_SIGNING_ALLOWED=NO \
  SWIFT_STRICT_CONCURRENCY=complete \
  -jobs 1 \
  2>&1 | tee "$run_directory/xcodebuild.log"

xcrun xcresulttool get test-results summary \
  --path "$result_bundle" \
  > "$summary_file"

node - "$summary_file" "$expected_total_tests" <<'NODE'
const fs = require("node:fs");

const summaryPath = process.argv[2];
const expectedTotal = Number(process.argv[3]);
const summary = JSON.parse(fs.readFileSync(summaryPath, "utf8"));
const passed = Number(summary.passedTests ?? 0);
const failed = Number(summary.failedTests ?? 0);
const skipped = Number(summary.skippedTests ?? 0);
const total = Number(summary.totalTestCount ?? 0);

if (
  summary.result !== "Passed" ||
  total !== expectedTotal ||
  passed !== expectedTotal ||
  failed !== 0 ||
  skipped !== 0
) {
  console.error(
    `error: expected ${expectedTotal}/${expectedTotal} passed with no failures or skips; ` +
    `result=${summary.result}, total=${total}, passed=${passed}, failed=${failed}, skipped=${skipped}`
  );
  process.exit(1);
}
NODE

echo "Quality gate passed: $expected_total_tests/$expected_total_tests XCTest cases, SSV, configuration and shipping-source checks."
echo "Evidence: $run_directory"
