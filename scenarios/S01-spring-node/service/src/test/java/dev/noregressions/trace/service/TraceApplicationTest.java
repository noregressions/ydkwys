package dev.noregressions.trace.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.beans.factory.annotation.Autowired;

@SpringBootTest
class TraceApplicationTest {
    @Autowired
    private TraceController controller;

    @Test
    void contextLoadsAndNormalizerIsUsable() {
        assertThat(controller.trace("  Hello   Supply Chain  ").get("normalized"))
                .isEqualTo("hello supply chain");
    }
}
