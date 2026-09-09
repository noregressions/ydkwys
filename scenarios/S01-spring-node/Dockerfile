FROM eclipse-temurin:21-jre-jammy

WORKDIR /app
COPY service/target/service-1.0.0.jar /app/checkout-service.jar

EXPOSE 8080
USER 10001
ENTRYPOINT ["java", "-jar", "/app/checkout-service.jar"]
