---
id: setup-build-manual
oneliner: "Step-by-step manual execution procedures corresponding to build-all.sh."
track: reference
---

# Building by Hand

Manual execution instructions corresponding to `./scripts/build-all.sh`. Use these commands for targeted debugging of specific build or cache initialization failures.

## 1. Clone or Update Repository

```command
git clone https://github.com/noregressions/ydkwys.git
cd ydkwys
```

To update:

```command
git pull
```

## 2. Pull Container Base Images

Base images utilized across scenarios: `eclipse-temurin:21-jre-jammy` (S01) and `payara/server-web:7.2026.7` (S02).

Docker:

```command
docker pull eclipse-temurin:21-jre-jammy
docker pull payara/server-web:7.2026.7
```

Podman:

```command
podman pull docker.io/library/eclipse-temurin:21-jre-jammy
podman pull docker.io/payara/server-web:7.2026.7
```

Verify image presence:

```command
docker image inspect eclipse-temurin:21-jre-jammy >/dev/null && \
docker image inspect payara/server-web:7.2026.7 >/dev/null && \
echo "Base images available"
```

## 3. Build the Maven Scenarios

Compile the Java scenario modules, populating the local repository cache (`~/.m2/repository`):

```command
cd scenarios/S01-spring-node && ./scripts/build.sh && cd ../..
cd scenarios/S02-payara-mvnpm && ./scripts/build.sh && cd ../..
cd scenarios/S04-maven-plugin-hidden-content && ./scripts/build.sh && cd ../..
```

## 4. Build the npm Scenario

Install npm dependencies and validate execution of package lifecycle hooks:

```command
cd scenarios/S05-node-prepack && ./scripts/build.sh && cd ../..
```

## 5. Build the Python Scenario

Initialize the Python virtual environment and local package dependencies:

```command
cd scenarios/S03-python-pep517 && ./scripts/build.sh && cd ../..
```

## 6. Initialize Grype Vulnerability Database

```command
grype db update
grype db status
```

Confirm that `db status` reports an initialized local database.

## 7. Initialize Trivy Vulnerability Database

Execute a filesystem scan against S01 to populate the local Trivy vulnerability database:

```command
trivy fs --scanners vuln --no-progress scenarios/S01-spring-node
```

## 8. Initialize Syft Cache

```command
syft scenarios/S01-spring-node -o table >/dev/null
syft version
```

## 9. Verify Snyk CLI Authentication

```command
snyk auth
snyk --version
```

Optional baseline execution:

```command
cd investigations/T01-snyk-beyond-sbom
./scripts/baseline.sh
cd ../..
```

## 10. Initialize OWASP Dependency-Check NVD Cache

Export `NVD_API_KEY`:

```command
printenv NVD_API_KEY >/dev/null && echo "NVD_API_KEY is exported"
```

Run initialization:

```command
cd investigations/T06-owasp-dependency-check-s04
./scripts/baseline-s04.sh
./scripts/run-dependency-check-s04.sh
cd ../..
```

Local vulnerability data is cached in `~/.cache/kcdc-dependency-check/<version>`.

## 11. Verify Docker Scout Integration

```command
docker scout version
```

Verify local scenario images are accessible in the local image registry:

```command
docker images | grep -E 'checkout-service|payara-mvnpm-trace-lab'
```

## 12. Complete Verification Check

```command
./scripts/tools-check.sh
printenv NVD_API_KEY >/dev/null && echo "NVD API key: configured" || echo "NVD API key: not configured"
docker image inspect eclipse-temurin:21-jre-jammy >/dev/null && \
docker image inspect payara/server-web:7.2026.7 >/dev/null && \
echo "Workshop base images ready"
```
