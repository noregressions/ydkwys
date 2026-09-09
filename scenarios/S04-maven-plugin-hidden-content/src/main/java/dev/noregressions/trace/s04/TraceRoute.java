package dev.noregressions.trace.s04;

/**
 * Extension point used by the application.
 *
 * The application source does not contain the workshop's hidden route.
 * Implementations may be supplied on the runtime class path.
 */
public interface TraceRoute {
    String path();
    String responseJson();
}
