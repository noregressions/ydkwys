package dev.noregressions.trace.normalizer;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

class TraceNormalizerTest {
    @Test
    void normalizesAndHashes() {
        var value = TraceNormalizer.normalize("  Hello   Supply Chain  ");
        assertEquals("hello supply chain", value.normalized());
        assertEquals(64, value.sha256().length());
    }
}
