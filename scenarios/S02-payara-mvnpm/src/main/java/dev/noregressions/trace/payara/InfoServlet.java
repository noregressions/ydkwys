package dev.noregressions.trace.payara;

import java.io.IOException;

import org.apache.commons.lang3.StringUtils;

import jakarta.json.Json;
import jakarta.json.JsonObject;
import jakarta.servlet.ServletException;
import jakarta.servlet.annotation.WebServlet;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@WebServlet("/api/info")
public class InfoServlet extends HttpServlet {

    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response)
            throws ServletException, IOException {

        String rawName = request.getParameter("name");
        String name = StringUtils.defaultIfBlank(rawName, "mixed supply chain");
        String displayName = StringUtils.capitalize(name);

        JsonObject body = Json.createObjectBuilder()
                .add("message", "Hello " + displayName)
                .add("application", "payara-mvnpm-trace-lab")
                .add("javaLibrary", "commons-lang3")
                .add("server", "Payara")
                .build();

        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write(body.toString());
    }
}
