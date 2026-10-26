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
