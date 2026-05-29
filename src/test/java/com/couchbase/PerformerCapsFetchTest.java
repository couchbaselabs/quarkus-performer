package com.couchbase;

import com.couchbase.client.protocol.performer.PerformerCapsFetchRequest;
import com.couchbase.client.protocol.performer.PerformerCapsFetchResponse;
import io.grpc.stub.StreamObserver;
import io.quarkus.test.junit.QuarkusTest;
import org.junit.jupiter.api.Test;

import java.util.concurrent.atomic.AtomicReference;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Exercises the real JavaPerformer.performerCapsFetch path under the Quarkus classloader.
 * This is exactly what failed before with NoClassDefFoundError: CoreTransactionsExtension.
 */
@QuarkusTest
public class PerformerCapsFetchTest {

    @Test
    public void performerCapsFetchSucceeds() {
        var performer = new JavaPerformer();
        var result = new AtomicReference<PerformerCapsFetchResponse>();
        var error = new AtomicReference<Throwable>();

        performer.performerCapsFetch(PerformerCapsFetchRequest.newBuilder().build(),
                new StreamObserver<>() {
                    @Override public void onNext(PerformerCapsFetchResponse value) { result.set(value); }
                    @Override public void onError(Throwable t) { error.set(t); }
                    @Override public void onCompleted() { }
                });

        if (error.get() != null) {
            error.get().printStackTrace(System.out);
        }
        assertNull(error.get(), "performerCapsFetch should not error");
        assertNotNull(result.get(), "performerCapsFetch should return a response");
        System.out.println("libraryVersion = " + result.get().getLibraryVersion());
        System.out.println("transactionsProtocolVersion = " + result.get().getTransactionsProtocolVersion());
        System.out.println("transactionImplementationsCaps count = "
                + result.get().getTransactionImplementationsCapsCount());
        // The version should be introspected from the SDK jar manifest, not the "3.5.0" hard-coded
        // fallback that signals introspection failed under the Quarkus classloader.
        assertNotEquals("3.5.0", result.get().getLibraryVersion(),
                "SDK version should be introspected, not the 3.5.0 fallback");
        // Loading the transaction extensions used to throw NoClassDefFoundError: CoreTransactionsExtension
        // due to a split package across the Quarkus dev-mode classloaders.
        assertTrue(result.get().getTransactionImplementationsCapsCount() > 0,
                "transaction extension caps should be populated");
    }
}
