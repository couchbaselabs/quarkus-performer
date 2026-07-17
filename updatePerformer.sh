counter=1

#echo "$counter - Fetching Couchbase Java SDK version and Quarkus version from quarkus-couchbase"
#((counter++))
#POM_CONTENT=$(curl -s https://raw.githubusercontent.com/quarkiverse/quarkus-couchbase/main/pom.xml)
#SDK_VERSION=$(echo "$POM_CONTENT" | awk -F'[<>]' '/couchbase.client.version/ {print $3}' | tr -d '[:space:]')
#QUARKUS_VERSION=$(echo "$POM_CONTENT" | grep -E '<quarkus\.version>' | grep -v 'platform' | awk -F'[<>]' '{print $3}' | tr -d '[:space:]')
#if [ -z "$SDK_VERSION" ]; then
#  echo "Error: Failed to fetch SDK version"
#  exit 1
#fi
#if [ -z "$QUARKUS_VERSION" ]; then
#  echo "Error: Failed to fetch Quarkus version"
#  exit 1
#fi

SDK_VERSION=3.13.0
QUARKUS_VERSION=3.36.3
echo "Detected SDK version: $SDK_VERSION"
echo "Detected Quarkus version: $QUARKUS_VERSION"

echo "$counter - Updating Quarkus version in local pom.xml"
((counter++))
sed -i '' "s|<quarkus.platform.version>[^<]*</quarkus.platform.version>|<quarkus.platform.version>${QUARKUS_VERSION}</quarkus.platform.version>|" pom.xml

echo "$counter - Cloning couchbase-jvm-clients (tag: $SDK_VERSION)"
((counter++))

# Step 1: Clone the repository with no files checked out
git clone -n --filter=blob:none --sparse git@github.com:couchbase/couchbase-jvm-clients.git
cd couchbase-jvm-clients || exit
# Fetch the specific tag
git fetch origin tag "$SDK_VERSION" --depth=1
git sparse-checkout set --no-cone /core-fit-performer/src/main/java/ /java-fit-performer/src/main/java/
git checkout "tags/$SDK_VERSION"

cd ..
echo "$counter - Cloning transactions-fit-performer"
((counter++))

git clone -n --depth=1 --filter=blob:none --sparse git@github.com:couchbaselabs/transactions-fit-performer.git
cd transactions-fit-performer || exit
git sparse-checkout set --no-cone /gRPC
git checkout

cd ..

echo "$counter - Copying files from Core and Java Performers"
((counter++))
cp -r couchbase-jvm-clients/core-fit-performer/src/main/java/com/couchbase/* src/main/java/com/couchbase/
cp -r couchbase-jvm-clients/java-fit-performer/src/main/java/com/couchbase/* src/main/java/com/couchbase/

echo "$counter - Copying .proto files from transactions-fit-performer"
((counter++))
cp -r transactions-fit-performer/gRPC/*.proto src/main/proto/

echo "$counter - Making ExpiryUtil use reflection for cross-classloader access"
((counter++))
# ExpiryUtil (copied from java-fit-performer) lives in the SDK's com.couchbase.client.core.transaction
# package so it can reach the package-private CoreTransactionAttemptContext.hasExpiredClientSide.
# In Quarkus dev mode ExpiryUtil and CoreTransactionAttemptContext load in different classloaders,
# so a direct package-private call throws IllegalAccessError. Reflection with setAccessible(true)
# works across classloaders (and in the production jar and native image). The reflected method is
# registered in src/main/resources/META-INF/native-image/reflect-config.json for native image.
cat > src/main/java/com/couchbase/client/core/transaction/ExpiryUtil.java <<'EXPIRY_EOF'
/*
 * Copyright 2022 Couchbase, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
// [skip:<3.3.0]
package com.couchbase.client.core.transaction;

import java.lang.reflect.Method;
import java.util.Optional;

/**
 * These methods need to access a package-private method on {@link CoreTransactionAttemptContext}.
 *
 * <p>The call is made via reflection rather than directly because under Quarkus dev mode the
 * performer's own classes (loaded by the reloadable classloader) and the SDK (loaded by the base
 * runtime classloader) live in different classloaders. A compile-time package-private call across
 * those classloaders fails at runtime with {@code IllegalAccessError}, since the JVM's runtime
 * package identity is (classloader + package name). {@code setAccessible(true)} bypasses that check,
 * so this works in dev mode, the production runner jar, and native image alike. The reflected method
 * is registered in {@code META-INF/native-image/reflect-config.json} so it remains invocable in the
 * native image.
 */
public class ExpiryUtil {
    private ExpiryUtil() {}

    private static final Method HAS_EXPIRED_CLIENT_SIDE;

    static {
        try {
            HAS_EXPIRED_CLIENT_SIDE = CoreTransactionAttemptContext.class
                    .getDeclaredMethod("hasExpiredClientSide", String.class, Optional.class);
            HAS_EXPIRED_CLIENT_SIDE.setAccessible(true);
        } catch (NoSuchMethodException e) {
            throw new ExceptionInInitializerError(e);
        }
    }

    public static boolean hasExpired(CoreTransactionAttemptContext ctx, String stage, Optional<String> docId) {
        try {
            return (boolean) HAS_EXPIRED_CLIENT_SIDE.invoke(ctx, stage, docId);
        } catch (ReflectiveOperationException e) {
            throw new RuntimeException("Failed to invoke CoreTransactionAttemptContext.hasExpiredClientSide", e);
        }
    }
}
EXPIRY_EOF

echo "$counter - Removing main method from JavaPerformer"
((counter++))
./deleteMethod.sh "public static void main" "src/main/java/com/couchbase/JavaPerformer.java" "false"

echo "$counter - Replacing broken InsecureTrustManagerFactory import"
((counter++))
sed -i '' 's/import io.grpc.netty.shaded.io.netty.handler.ssl.util.InsecureTrustManagerFactory;/import com.couchbase.client.core.deps.io.netty.handler.ssl.util.InsecureTrustManagerFactory;/' src/main/java/com/couchbase/utils/OptionsUtil.java

echo "$counter - Adjusting performer for Quarkus compatibility"
((counter++))
sed -i '' '/response\.addPerformerCaps(Caps\.OBSERVABILITY_1);/d' src/main/java/com/couchbase/JavaPerformer.java
#Deleting the 3 lines configuring the custom scheduler
sed -i '' '/var userExecutorAndScheduler = UserSchedulerUtil\.userExecutorAndScheduler();/ {
  N
  N
  d
}' src/main/java/com/couchbase/JavaPerformer.java

#Make logger public
sed -i '' 's/private static final Logger logger = LoggerFactory.getLogger(JavaPerformer.class);/public static final Logger logger = LoggerFactory.getLogger(JavaPerformer.class);/' src/main/java/com/couchbase/JavaPerformer.java

#Deletes the body of UserSchedulerUtil.assertInCustomUserSchedulerThread
./deleteMethod.sh "private static void assertInCustomUserSchedulerThread" "src/main/java/com/couchbase/utils/UserSchedulerUtil.java" "true"

echo "$counter - Delete cloned repositories"
((counter++))
rm -rf couchbase-jvm-clients
rm -rf transactions-fit-performer


