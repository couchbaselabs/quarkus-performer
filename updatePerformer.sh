#!/usr/bin/env bash
# Regenerates the performer from the Java FIT performer of one Couchbase Java SDK release, then
# applies the changes that Quarkus needs. Runs on macOS and Linux.
#
# Read the versions from a quarkus-couchbase checkout, so the performer matches what the extension ships:
#   QUARKUS_COUCHBASE_DIR=../quarkus-couchbase ./updatePerformer.sh
# Or set them directly:
#   SDK_VERSION=3.13.0 QUARKUS_VERSION=3.40.1 QUARKUS_COUCHBASE_VERSION=1.4.2 ./updatePerformer.sh
set -euo pipefail
cd "$(dirname "$0")"

SDK_REPO=${SDK_REPO:-https://github.com/couchbase/couchbase-jvm-clients.git}
MVN=${MVN:-mvn}
# Files under src/main/java that belong to this project. Everything else is copied from the SDK.
QUARKUS_FILES=(
  src/main/java/com/couchbase/QuarkusPerformer.java
  src/main/java/com/couchbase/ReflectionProcessing.java
)

if [ -n "${QUARKUS_COUCHBASE_DIR:-}" ]; then
  echo "Reading versions from $QUARKUS_COUCHBASE_DIR"
  QUARKUS_VERSION=$($MVN -q -f "$QUARKUS_COUCHBASE_DIR/pom.xml" help:evaluate -Dexpression=quarkus.version -DforceStdout)
  QUARKUS_COUCHBASE_VERSION=$($MVN -q -f "$QUARKUS_COUCHBASE_DIR/pom.xml" help:evaluate -Dexpression=project.version -DforceStdout)
  deps=$(mktemp)
  $MVN -q -f "$QUARKUS_COUCHBASE_DIR/runtime/pom.xml" dependency:list -DincludeArtifactIds=java-client -DoutputFile="$deps"
  SDK_VERSION=$(grep -oE 'com\.couchbase\.client:java-client:jar:[^:]+' "$deps" | cut -d: -f4)
  rm -f "$deps"
fi
: "${SDK_VERSION:?Set SDK_VERSION or QUARKUS_COUCHBASE_DIR}"
: "${QUARKUS_VERSION:?Set QUARKUS_VERSION or QUARKUS_COUCHBASE_DIR}"
: "${QUARKUS_COUCHBASE_VERSION:?Set QUARKUS_COUCHBASE_VERSION or QUARKUS_COUCHBASE_DIR}"
echo "Java SDK $SDK_VERSION, Quarkus $QUARKUS_VERSION, quarkus-couchbase $QUARKUS_COUCHBASE_VERSION"

# Applies a perl substitution to a file. Fails when the file does not change, so a patch that no
# longer matches the upstream code stops the update instead of being skipped.
patch_file() {
  local file=$1 expr=$2 before
  before=$(cksum < "$file")
  perl -0pi -e "$expr" "$file"
  if [ "$before" = "$(cksum < "$file")" ]; then
    echo "Patch did not apply to $file: $expr" >&2
    exit 1
  fi
}

echo "Updating versions in pom.xml"
perl -0pi -e "s|<quarkus.platform.version>[^<]*<|<quarkus.platform.version>${QUARKUS_VERSION}<|" pom.xml
perl -0pi -e "s|<couchbase-client.version>[^<]*<|<couchbase-client.version>${SDK_VERSION}<|" pom.xml
perl -0pi -e "s|<quarkus-couchbase.version>[^<]*<|<quarkus-couchbase.version>${QUARKUS_COUCHBASE_VERSION}<|" pom.xml

echo "Fetching the FIT performer and protocol from couchbase-jvm-clients $SDK_VERSION"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git clone -q --depth=1 --filter=blob:none --no-checkout --branch "$SDK_VERSION" "$SDK_REPO" "$work/sdk"
git -C "$work/sdk" sparse-checkout set --no-cone \
  /core-fit-performer/src/main/java/ \
  /java-fit-performer/src/main/java/ \
  /fit-performer-protocol/fit-protocol/operational/
git -C "$work/sdk" checkout -q
protocol="$work/sdk/fit-performer-protocol/fit-protocol/operational"
if [ ! -d "$protocol" ]; then
  echo "SDK $SDK_VERSION has no fit-performer-protocol/fit-protocol/operational directory" >&2
  exit 1
fi

echo "Replacing the copied sources and protos"
keep=$(mktemp -d)
for f in "${QUARKUS_FILES[@]}"; do mkdir -p "$keep/$(dirname "$f")" && cp "$f" "$keep/$f"; done
rm -rf src/main/java src/main/proto
mkdir -p src/main/java src/main/proto
cp -R "$work/sdk/core-fit-performer/src/main/java/." src/main/java/
cp -R "$work/sdk/java-fit-performer/src/main/java/." src/main/java/
cp "$protocol"/*.proto src/main/proto/
cp -R "$keep/src/main/java/." src/main/java/
cp -R quarkus-overrides/. src/main/java/
rm -rf "$keep"

echo "Applying Quarkus changes"
# Quarkus runs a gRPC method on a worker thread only when it or its declaring class has @Blocking.
# The performer blocks on the SDK in every RPC, so none of them may run on the event loop.
patch_file src/main/java/com/couchbase/client/performer/core/CorePerformer.java \
  's/^(abstract public class CorePerformer |public abstract class CorePerformer )/\@io.smallrye.common.annotation.Blocking\n$1/m'
patch_file src/main/java/com/couchbase/JavaPerformer.java \
  's/^public class JavaPerformer /\@io.smallrye.common.annotation.Blocking\npublic class JavaPerformer /m'
# Quarkus excludes grpc-netty-shaded. Use the copy of the class that the SDK shades.
patch_file src/main/java/com/couchbase/utils/OptionsUtil.java \
  's/import io\.grpc\.netty\.shaded\.io\.netty\.handler\.ssl\.util\.InsecureTrustManagerFactory;/import com.couchbase.client.core.deps.io.netty.handler.ssl.util.InsecureTrustManagerFactory;/'
# The performer does not support the OpenTelemetry observability tests.
patch_file src/main/java/com/couchbase/JavaPerformer.java \
  's/^\s*response\.addPerformerCaps\(Caps\.OBSERVABILITY_1\);\n//m'

echo "Done. Build with: mvn clean package (add -Dnative for a native executable)"
