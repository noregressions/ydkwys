package dev.noregressions.trace.plugin;

import org.apache.maven.model.Resource;
import org.apache.maven.plugin.AbstractMojo;
import org.apache.maven.plugin.MojoExecutionException;
import org.apache.maven.plugins.annotations.LifecyclePhase;
import org.apache.maven.plugins.annotations.Mojo;
import org.apache.maven.plugins.annotations.Parameter;
import org.apache.maven.project.MavenProject;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;

@Mojo(
        name = "inject-route",
        defaultPhase = LifecyclePhase.GENERATE_SOURCES,
        threadSafe = true
)
public final class InjectRouteMojo extends AbstractMojo {

    private static final String PAYLOAD_RESOURCE = "trace-route.properties";
    private static final String GENERATED_CLASS =
            "dev.noregressions.trace.s04.generated.GeneratedTraceRoute";
    private static final String SERVICE_INTERFACE =
            "dev.noregressions.trace.s04.TraceRoute";

    @Parameter(defaultValue = "${project}", readonly = true, required = true)
    private MavenProject project;

    @Override
    public void execute() throws MojoExecutionException {
        Properties payload = loadPayload();

        String path = require(payload, "path");
        String message = require(payload, "message");
        String origin = require(payload, "origin");

        Path build = project.getBasedir().toPath().resolve("target");
        Path sourceRoot = build.resolve("generated-sources/trace-injector");
        Path resourceRoot = build.resolve("generated-resources/trace-injector");

        try {
            writeGeneratedJava(sourceRoot, path, message, origin);
            writeServiceDescriptor(resourceRoot);
            writeInjectionMetadata(resourceRoot, path, origin);

            project.addCompileSourceRoot(sourceRoot.toString());

            Resource resource = new Resource();
            resource.setDirectory(resourceRoot.toString());
            resource.setFiltering(false);
            project.addResource(resource);

            getLog().info("Injected TraceRoute source from plugin payload: " + origin);
            getLog().info("Injected route: " + path);
        } catch (IOException e) {
            throw new MojoExecutionException("Failed to generate trace route", e);
        }
    }

    private Properties loadPayload() throws MojoExecutionException {
        ClassLoader loader = getClass().getClassLoader();

        try (InputStream in = loader.getResourceAsStream(PAYLOAD_RESOURCE)) {
            if (in == null) {
                throw new MojoExecutionException(
                        "Plugin payload resource not found on plugin classpath: "
                                + PAYLOAD_RESOURCE);
            }

            Properties properties = new Properties();
            properties.load(in);
            return properties;
        } catch (IOException e) {
            throw new MojoExecutionException("Failed to read plugin payload", e);
        }
    }

    private static String require(Properties properties, String key)
            throws MojoExecutionException {
        String value = properties.getProperty(key);
        if (value == null || value.isBlank()) {
            throw new MojoExecutionException("Missing plugin payload property: " + key);
        }
        return value.trim();
    }

    private static void writeGeneratedJava(
            Path sourceRoot,
            String routePath,
            String message,
            String origin
    ) throws IOException {

        Path source = sourceRoot.resolve(
                "dev/noregressions/trace/s04/generated/GeneratedTraceRoute.java");

        Files.createDirectories(source.getParent());

        String response =
                "{\n"
                        + "  \"message\": \"" + jsonText(message) + "\",\n"
                        + "  \"origin\": \"" + jsonText(origin) + "\",\n"
                        + "  \"introducedBy\": \"trace-injector-maven-plugin\",\n"
                        + "  \"route\": \"" + jsonText(routePath) + "\"\n"
                        + "}\n";

        String java = """
                package dev.noregressions.trace.s04.generated;

                import dev.noregressions.trace.s04.TraceRoute;

                public final class GeneratedTraceRoute implements TraceRoute {

                    @Override
                    public String path() {
                        return %s;
                    }

                    @Override
                    public String responseJson() {
                        return %s;
                    }
                }
                """.formatted(
                        javaLiteral(routePath),
                        javaLiteral(response)
                );

        Files.writeString(source, java, StandardCharsets.UTF_8);
    }

    private static void writeServiceDescriptor(Path resourceRoot) throws IOException {
        Path service = resourceRoot.resolve("META-INF/services/" + SERVICE_INTERFACE);
        Files.createDirectories(service.getParent());
        Files.writeString(
                service,
                GENERATED_CLASS + System.lineSeparator(),
                StandardCharsets.UTF_8
        );
    }

    private static void writeInjectionMetadata(
            Path resourceRoot,
            String routePath,
            String origin
    ) throws IOException {

        Path metadata = resourceRoot.resolve(
                "META-INF/trace-lab/plugin-injection.properties");

        Files.createDirectories(metadata.getParent());

        String data =
                "plugin=trace-injector-maven-plugin\n"
                        + "payload=" + origin + "\n"
                        + "route=" + routePath + "\n";

        Files.writeString(metadata, data, StandardCharsets.UTF_8);
    }

    private static String javaLiteral(String value) {
        return "\""
                + value.replace("\\", "\\\\")
                       .replace("\"", "\\\"")
                       .replace("\r", "\\r")
                       .replace("\n", "\\n")
                + "\"";
    }

    private static String jsonText(String value) {
        return value.replace("\\", "\\\\")
                    .replace("\"", "\\\"")
                    .replace("\r", "\\r")
                    .replace("\n", "\\n");
    }
}
