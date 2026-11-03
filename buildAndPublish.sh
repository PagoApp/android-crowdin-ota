set -euo pipefail

VERSION="${1:?usage: ./buildAndPublish.sh <versionName>}"

./gradlew clean -p crowdin -x lint build -PversionName="$VERSION"
# publishGithub is finalizedBy `publish`, which uploads to BOTH maven repos (GitHubPackages + Artifactory).
./gradlew -p crowdin publishGithub -PversionName="$VERSION"

# Integrators resolve from either remote: Artifactory android-pago (BCR, Erste) or GitHub Packages. A version
# on only one of them breaks SDK releases that pin it (HYP-840: 1.10.1_5 reached GitHub only), so verify both.
prop() {
  [ -f github.properties ] || return 0
  awk -v k="$1" '{ line=$0; sub(/\r$/, "", line); i=index(line, "="); if (i == 0) next;
    key=substr(line, 1, i-1); gsub(/[ \t]/, "", key);
    if (key == k) { val=substr(line, i+1); sub(/^[ \t]+/, "", val); sub(/[ \t]+$/, "", val); print val; exit } }' github.properties
}
AF_USER="$(prop gpr.artifactory_user)"; AF_USER="${AF_USER:-${GPR_ARTIFACTORY_USER:-}}"
AF_PASS="$(prop gpr.artifactory_password)"; AF_PASS="${AF_PASS:-${GPR_ARTIFACTORY_PASSWORD:-}}"
GH_USER="$(prop gpr.usr)"; GH_USER="${GH_USER:-${GPR_USER:-}}"
GH_KEY="$(prop gpr.key)"; GH_KEY="${GH_KEY:-${GPR_API_KEY:-}}"

ARTIFACT_PATH="app/pago/crowdin-ota/$VERSION/crowdin-ota-$VERSION"
missing=0
check() {
  local remote="$1" url="$2" creds="$3" status
  status="$(curl -s -o /dev/null -w '%{http_code}' -I -u "$creds" "$url" || true)"
  if [ "$status" = "200" ]; then
    echo "OK      $remote  $url"
  else
    echo "MISSING $remote  $url  (HTTP $status)" >&2
    missing=1
  fi
}
for ext in pom aar; do
  check artifactory "https://artifactory.pago.cloud/artifactory/android-pago/$ARTIFACT_PATH.$ext" "$AF_USER:$AF_PASS"
  check github "https://maven.pkg.github.com/PagoApp/android-crowdin-ota/$ARTIFACT_PATH.$ext" "$GH_USER:$GH_KEY"
done

if [ "$missing" -ne 0 ]; then
  echo "crowdin-ota $VERSION is NOT on both remotes. Re-run the publish (Artifactory needs VPN / a whitelisted IP) before any SDK pins it." >&2
  exit 1
fi
echo "crowdin-ota $VERSION is published on Artifactory and GitHub Packages."
