#!/bin/zsh
set -euo pipefail

project_root=${0:A:h:h}
entitlements_path="$project_root/Copydalis/Resources/Copydalis.entitlements"

contains_fixed() {
  local pattern=$1
  local path=$2
  if (( $+commands[rg] )); then
    rg --quiet --fixed-strings "$pattern" "$path"
  else
    /usr/bin/grep -Fq -- "$pattern" "$path"
  fi
}

swift_sources_contain() {
  local pattern=$1
  local source_file
  if (( $+commands[rg] )); then
    rg --quiet --glob '*.swift' --fixed-strings "$pattern" "$project_root/Copydalis"
    return
  fi

  while IFS= read -r -d '' source_file; do
    if /usr/bin/grep -Fq -- "$pattern" "$source_file"; then
      return 0
    fi
  done < <(/usr/bin/find "$project_root/Copydalis" -type f -name '*.swift' -print0)
  return 1
}

plutil -lint "$entitlements_path" >/dev/null

if ! contains_fixed 'ENABLE_HARDENED_RUNTIME: YES' "$project_root/project.yml"; then
  print -u2 'Hardened Runtime must remain enabled.'
  exit 1
fi

if ! contains_fixed 'ENABLE_APP_SANDBOX: NO' "$project_root/project.yml"; then
  print -u2 'The reviewed Developer ID distribution profile changed unexpectedly.'
  exit 1
fi

if ! contains_fixed 'CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO' "$project_root/project.yml"; then
  print -u2 'Release builds must not receive development base entitlements.'
  exit 1
fi

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

for forbidden_pattern in 'URLSession' 'NWConnection' 'socket(' 'getaddrinfo(' 'Process(' 'NSLog(' 'print(' 'osascript'; do
  if swift_sources_contain "$forbidden_pattern"; then
    print -u2 "Forbidden production-source pattern found: $forbidden_pattern"
    exit 1
  fi
done

for forbidden_framework in 'Network.framework' 'CFNetwork.framework' 'WebKit.framework'; do
  if contains_fixed "$forbidden_framework" "$project_root/project.yml"; then
    print -u2 "Forbidden production framework found: $forbidden_framework"
    exit 1
  fi
done

if contains_fixed '.package(' "$project_root/Package.swift"; then
  print -u2 'Runtime package dependencies require an approved security review.'
  exit 1
fi

print 'Security baseline checks passed.'
