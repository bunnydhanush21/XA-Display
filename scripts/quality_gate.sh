#!/usr/bin/env bash
# Objective checks for docs/QUALITY_SCORECARD.md.
# Device-only measurements are recorded as device-pending. They are not invented.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail() { echo "quality gate: $*" >&2; exit 1; }

echo "== SwiftLint =="
if command -v swiftlint >/dev/null 2>&1; then
  swiftlint lint --strict
elif [[ -x /tmp/swiftlint/swiftlint ]]; then
  /tmp/swiftlint/swiftlint lint --strict
else
  echo "swiftlint not installed; CI installs 0.65.1 before this script"
fi

echo "== warnings as errors and strict concurrency (protocol) =="
export PATH="${SWIFT_PATH:-/tmp/swift-install/usr/bin:$PATH}"
swift build -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete
swift test -Xswiftc -warnings-as-errors -Xswiftc -strict-concurrency=complete --enable-code-coverage

echo "== protocol line coverage >= 80% =="
PROF="$(find .build -name 'default.profdata' | head -n 1)"
BUNDLE="$(find .build -name 'XADisplayProtocolPackageTests.xctest' | head -n 1)"
if [[ -d "$BUNDLE" ]]; then
  BIN="$BUNDLE/Contents/MacOS/XADisplayProtocolPackageTests"
elif [[ -n "$BUNDLE" ]]; then
  BIN="$BUNDLE"
else
  BIN="$(find .build -type f -name 'XADisplayProtocolPackageTests' | head -n 1)"
fi
[[ -n "$PROF" && -n "$BIN" && -e "$BIN" ]] || fail "coverage profile missing"
if command -v llvm-cov >/dev/null 2>&1; then
  LLVM_COV="$(command -v llvm-cov)"
else
  LLVM_COV="$(xcrun --find llvm-cov)"
fi
LINE="$("$LLVM_COV" report -instr-profile "$PROF" -ignore-filename-regex='Tests/' "$BIN" | awk '/^TOTAL/ {
  for (i = 1; i <= NF; i++) if ($i ~ /%$/) p[++n] = $i
  print p[3]
}')"
LINE="${LINE%%%}"
python3 - "$LINE" << 'PY'
import sys
value = float(sys.argv[1])
print(f"protocol line coverage {value:.2f}%")
if value < 80:
    raise SystemExit("protocol line coverage below 80%")
PY

echo "== fuzz, state machine, typed errors, loggers, docs =="
python3 - << 'PY'
from pathlib import Path
root = Path(".")
text = Path("Tests/XADisplayProtocolTests/QualityTests.swift").read_text()
for needle in ["XAInputMessage.decode", "VideoControlMessage.parse", "UDPVideoPacket.decode", "AnnexB.parse", "BatteryCareOp.parse", "ChromeWire.parseWindows", "FrameParser", "XASettingsDocument.decode"]:
    if needle not in text:
        raise SystemExit(f"fuzz test missing {needle}")
state = Path("Tests/XADisplayProtocolTests/ArchitectureTests.swift").read_text() + Path("Tests/XADisplayProtocolTests/QualityTests.swift").read_text()
if "ConnectionMachine.reduce" not in state:
    raise SystemExit("connection state machine tests missing")
for name in ["Sources/XADisplayProtocol/ChannelAuth.swift", "macos/XADisplayHost/HostError.swift", "ios/XADisplay/PadError.swift"]:
    body = Path(name).read_text()
    if "enum " not in body or "Error" not in body:
        raise SystemExit(f"typed error missing in {name}")
components = [
    "macos/XADisplayHost/HostController+3.swift",
    "macos/XADisplayHost/CapturePipeline.swift",
    "macos/XADisplayHost/H264Encoder.swift",
    "macos/XADisplayHost/AudioCapture.swift",
    "macos/XADisplayHost/UsbmuxClient.swift",
    "macos/XADisplayHost/EventPoster.swift",
    "macos/XADisplayHost/WindowMover.swift",
    "macos/XADisplayHost/AppDelegate.swift",
    "macos/XADisplayHost/MenuPopover.swift",
    "macos/XADisplayHost/OnboardingFlow.swift",
    "macos/XADisplayHost/XALog.swift",
    "ios/XADisplay/VideoReceiver.swift",
    "ios/XADisplay/InputChannel.swift",
    "ios/XADisplay/AppDelegate.swift",
    "ios/XADisplay/MacBrowser.swift",
    "ios/XADisplay/BatteryAccess.swift",
    "ios/XADisplay/XALog.swift",
    "ios/XADisplay/ReceiverViewController+2.swift",
]
for path in components:
    body = Path(path).read_text()
    if "XALog" not in body and "os.Logger" not in body and "OSLog" not in body:
        raise SystemExit(f"logger missing in {path}")
if "com.bunnydhanush.xadisplay" not in Path("macos/XADisplayHost/XALog.swift").read_text():
    raise SystemExit("Mac logger subsystem missing")
if "OSLog" not in Path("ios/XADisplay/XALog.swift").read_text():
    raise SystemExit("iPad logger missing; os.Logger is unavailable on iOS 12")
import re
pat = re.compile(r"^(\s*)public\s+(?:final\s+)?(?:struct|enum|class|actor)\s+")
missing = []
for path in list(Path("Sources").rglob("*.swift")):
    lines = path.read_text().splitlines()
    for i, line in enumerate(lines):
        if not pat.match(line):
            continue
        j = i - 1
        while j >= 0 and lines[j].strip() == "":
            j -= 1
        if j < 0 or not lines[j].strip().startswith("///"):
            missing.append(f"{path}:{i+1}")
if missing:
    raise SystemExit("undocumented public types:\n" + "\n".join(missing[:20]))
yml = Path("macos/project.yml").read_text()
host = "\n".join(path.read_text() for path in Path("macos").rglob("*.swift"))
if "@unchecked Sendable" in host:
    raise SystemExit("@unchecked Sendable is still present in the Mac target")
if "SWIFT_STRICT_CONCURRENCY: complete" not in yml:
    raise SystemExit("Mac target is not set to strict concurrency complete")
if "SWIFT_TREAT_WARNINGS_AS_ERRORS: YES" not in yml or "SWIFT_TREAT_WARNINGS_AS_ERRORS: YES" not in Path("ios/project.yml").read_text():
    raise SystemExit("warnings-as-errors is not set on both apps")
print("static checks passed")
PY

echo "== benchmarks =="
mkdir -p "$ROOT/build/quality"
QUALITY_BENCH_DIR="$ROOT/build/quality" swift test -Xswiftc -warnings-as-errors --filter QualityTests.testSyntheticLoopbackPacingAndReconnectBudget
python3 - << 'PY'
import json
from pathlib import Path
path = Path("build/quality/loopback.json")
if not path.exists():
    raise SystemExit("synthetic benchmark file missing")
report = json.loads(path.read_text())
for key in ["encode_transport_glass_ms", "ipad_memory_mb", "device_reconnect_s"]:
    if report.get(key) != "device-pending":
        raise SystemExit(f"{key} must stay device-pending until a device measures it")
if not isinstance(report.get("loopback_reassembly_ms"), (int, float)):
    raise SystemExit("synthetic loopback number missing")
print("benchmarks", report)
PY

echo "== screenshots =="
python3 - << 'PY'
from pathlib import Path
# Placeholders are rejected. A real capture is optional and must be a non-trivial PNG.
pending = "device-pending" in Path("docs/QUALITY_SCORECARD.md").read_text()
shots = list(Path("docs/screenshots").glob("*.png")) if Path("docs/screenshots").exists() else []
for shot in shots:
    data = shot.read_bytes()
    if not data.startswith(b"\x89PNG") or len(data) < 8000:
        raise SystemExit(f"placeholder screenshot {shot}")
if not shots and not pending:
    raise SystemExit("screenshots missing and not marked device-pending")
print(f"screenshots: {len(shots)} file(s); device-pending allowed: {pending}")
PY

if [[ "$(uname -s)" == "Darwin" && "${QUALITY_XCODE:-0}" == "1" ]]; then
  echo "== Mac app build (strict concurrency, warnings as errors) =="
  (cd macos && xcodegen generate && xcodebuild \
    -project XADisplayHost.xcodeproj \
    -scheme XADisplayHost \
    -destination 'platform=macOS' \
    -configuration Debug \
    -derivedDataPath build \
    CODE_SIGNING_ALLOWED=NO \
    build)
fi

echo "quality gate passed"
