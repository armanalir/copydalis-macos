#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
entitlements_path="$project_root/Copydalis/Resources/Copydalis.entitlements"

plutil -lint "$entitlements_path" >/dev/null

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$entitlements_path" >/dev/null 2>&1; then
  print -u2 'Outgoing network entitlement is forbidden.'
  exit 1
fi

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.server' "$entitlements_path" >/dev/null 2>&1; then
  print -u2 'Incoming network entitlement is forbidden.'
  exit 1
fi

if /usr/libexec/PlistBuddy -c 'Print :com.apple.developer.icloud-services' "$entitlements_path" >/dev/null 2>&1; then
  print -u2 'iCloud entitlement is forbidden in V1.'
  exit 1
fi

for forbidden_pattern in 'URLSession' 'NWConnection' 'Process(' 'NSLog(' 'print(' 'osascript'; do
  if rg --glob '*.swift' --fixed-strings "$forbidden_pattern" "$project_root/Copydalis" >/dev/null; then
    print -u2 "Forbidden production-source pattern found: $forbidden_pattern"
    exit 1
  fi
done

print 'Security baseline checks passed.'
