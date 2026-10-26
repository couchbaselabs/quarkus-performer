package com.couchbase;

import com.couchbase.client.core.logging.LogRedaction;
import com.couchbase.client.core.logging.RedactionLevel;
import io.quarkus.grpc.GrpcService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import reactor.core.publisher.Hooks;

import java.util.Arrays;
import java.util.stream.Collectors;

/**
 * Runs the Java FIT performer as a Quarkus gRPC service.
 *
 * <p>updatePerformer.sh puts {@code @Blocking} on JavaPerformer and CorePerformer, which declare the
 * RPC methods, so Quarkus runs every RPC on a worker thread. An annotation on this class does not
 * reach inherited methods.
 *
 * <p>The static block repeats the setup that JavaPerformer.main does, because Quarkus starts the
 * gRPC server instead of main.
 */
@GrpcService
public class QuarkusPerformer extends JavaPerformer {
    private static final Logger logger = LoggerFactory.getLogger(QuarkusPerformer.class);

    static {
        System.setProperty("com.couchbase.transactions.debug.lock", "true");
        System.setProperty("com.couchbase.transactions.debug.monoBridge", "false");
        Hooks.onErrorDropped(err -> {
            // We intentionally don't set globalError here.
            // In a reactive chain, if one operation fails, any parallel operations are cancelled.
            // If those operations subsuquently hit an error, it has nowhere to go (as the original
            // chain has already had an error raised on it), and so it's raised on the global error
            // handle (e.g. here).  Though unfortunate, this is standard reactor UX, and shouldn't
            // be regarded as a test failure.
            logger.info("Async hook drop (probably fine, will happen if multiple concurrent operations in a reactor chain fail): {}\n\t{}",
                    err.toString(), Arrays.stream(err.getStackTrace()).map(StackTraceElement::toString).collect(Collectors.joining("\n\t")));
        });
        LogRedaction.setRedactionLevel(RedactionLevel.PARTIAL);
    }
}
