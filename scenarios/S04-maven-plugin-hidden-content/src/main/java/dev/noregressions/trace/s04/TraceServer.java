package dev.noregressions.trace.s04;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ServiceLoader;
import java.util.concurrent.Executors;

public final class TraceServer {

    private TraceServer() {
    }

    public static void main(String[] args) throws Exception {
        int port = Integer.parseInt(System.getenv().getOrDefault("PORT", "8082"));

        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", port), 0);

        server.createContext("/", exchange ->
                text(exchange, 200,
                        "Maven plugin hidden-content trace lab\n"
                                + "GET /health for the application endpoint.\n"));

        server.createContext("/health", exchange ->
                json(exchange, 200,
                        """
                        {
                          "application": "maven-plugin-hidden-content",
                          "status": "UP"
                        }
                        """));

        int loaded = 0;
        for (TraceRoute route : ServiceLoader.load(TraceRoute.class)) {
            server.createContext(route.path(), exchange ->
                    json(exchange, 200, route.responseJson()));
            loaded++;
        }

        server.setExecutor(Executors.newFixedThreadPool(4));
        server.start();

        System.out.printf("S04 listening on http://localhost:%d/%n", port);
        System.out.printf("Loaded %d TraceRoute service provider(s).%n", loaded);
    }

    private static void text(HttpExchange exchange, int status, String body) throws IOException {
        respond(exchange, status, "text/plain; charset=utf-8", body);
    }

    private static void json(HttpExchange exchange, int status, String body) throws IOException {
        respond(exchange, status, "application/json; charset=utf-8", body);
    }

    private static void respond(HttpExchange exchange, int status, String contentType, String body)
            throws IOException {
        byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", contentType);
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
        exchange.close();
    }
}
