package dev.noregressions.trace.normalizer;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Locale;
import org.apache.commons.codec.binary.Hex;

/**
 * Small library deliberately using commons-codec so the Shade Plugin has real
 * bytecode references to relocate.
 */
public final class TraceNormalizer {
    private TraceNormalizer() {
    }

    public static NormalizedValue normalize(String input) {
        String normalized = input == null
                ? ""
                : input.trim().replaceAll("\\s+", " ").toLowerCase(Locale.ROOT);

        return new NormalizedValue(normalized, sha256(normalized));
    }

    private static String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = digest.digest(value.getBytes(StandardCharsets.UTF_8));
            // This call is rewritten by the Shade Plugin to com.acme.internal.codec.binary.Hex.
            return Hex.encodeHexString(bytes);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 is required by the Java platform", e);
        }
    }

    public record NormalizedValue(String normalized, String sha256) {
    }
}
