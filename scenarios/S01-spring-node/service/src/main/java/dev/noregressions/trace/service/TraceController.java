package dev.noregressions.trace.service;

import dev.noregressions.trace.normalizer.TraceNormalizer;
import java.util.List;
import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class TraceController {

    @GetMapping("/trace")
    public Map<String, Object> trace(@RequestParam(name="value",defaultValue = "  Hello   Supply Chain  ") String value) {
        var normalized = TraceNormalizer.normalize(value);
        return Map.of(
                "input", value,
                "normalized", normalized.normalized(),
                "sha256", normalized.sha256(),
                "tracers", List.of("jackson-databind", "lodash", "commons-codec"));
    }
}
