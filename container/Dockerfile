# The WORKSHOP image: the code, prebuilt, on top of the tools image.
# Rebuilt whenever the workshop content changes — attendees who already
# have the base pull only these layers.
#
# Build:  ./container/build.sh          (from the repository root)
# Run:    ./container/run.sh
#
# Layering, so that editing a lesson does not redo every download:
#
#   code   — scenarios/ and scripts/ with all Markdown stripped. Cheap, and
#            it re-runs on every build; what matters is the checksum of what
#            it produces, which only moves when code moves.
#   build  — copies that code in and runs the prewarm. Docker caches this by
#            the checksum of the copied files, so as long as no code changed,
#            the Maven/npm/pip downloads and compiles are reused as-is.
#   final  — the full repository (docs, investigations, evidence) layered on
#            top. This is the only layer a documentation change rebuilds.

ARG BASE_IMAGE=shipping-workshop-base:latest

# --- code: build inputs only -------------------------------------------------
FROM ${BASE_IMAGE} AS code
COPY scenarios /src/scenarios
COPY scripts   /src/scripts
RUN find /src -name '*.md' -delete

# --- build: prewarm against the code-only tree --------------------------------
FROM ${BASE_IMAGE} AS build
WORKDIR /workshop
COPY --from=code /src/ /workshop/

# Prewarm everything code-shaped: all five scenario builds (Maven repo,
# npm cache, Python venv, S04's local fixture repo). Scanner databases are
# already in the base (--skip-db); image pulls and the S01/S02 image builds
# happen at run time via the host socket (--skip-pull --skip-images).
RUN chmod +x scripts/*.sh scenarios/*/scripts/*.sh \
    && ./scripts/build-all.sh --skip-pull --skip-images --skip-db

# Pre-resolve the Maven plugins the labs invoke ad hoc, so no lab is the
# first to download them. CycloneDX (S01/S02/S04/T01 SBOM steps) goes into
# the default ~/.m2; T06 runs Dependency-Check against S04's private local
# repo, so both versions its scripts can select are resolved there. The NVD
# dataset itself is not baked in: it is large, changes daily, and 13.0.0
# needs NVD_API_KEY, which is only passed at run time.
RUN cd scenarios/S02-payara-mvnpm \
    && mvn -q org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom -Dcyclonedx.skip=true \
    && cd ../S04-maven-plugin-hidden-content \
    && mvn -q -Dmaven.repo.local="$PWD/.maven-repo" \
         org.owasp:dependency-check-maven:12.2.2:help -Ddetail=false \
    && mvn -q -Dmaven.repo.local="$PWD/.maven-repo" \
         org.owasp:dependency-check-maven:13.0.0:help -Ddetail=false \
    && mvn -q -Dmaven.repo.local="$PWD/.maven-repo" \
         org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom -Dcyclonedx.skip=true

# S08 compares SBOM+ with the CycloneDX plugin. SBOM+ is vendored in the
# scenario, so seed it into both local repositories it is run from, then run
# the two scans once so the plugin's own dependencies are resolved, and
# discard the results.
RUN scenarios/S08-extended-sbom/scripts/seed-plugin.sh \
    && scenarios/S08-extended-sbom/scripts/seed-plugin.sh "$PWD/scenarios/S04-maven-plugin-hidden-content/.maven-repo" \
    && scenarios/S08-extended-sbom/scripts/scan-s04.sh >/dev/null \
    && scenarios/S08-extended-sbom/scripts/scan-s01.sh >/dev/null \
    && scenarios/S08-extended-sbom/scripts/clean.sh

# --- final: the whole repository on top of the prewarmed tree -----------------
FROM build

# ttyd serves the terminal half of the browser workshop view
# (container/web/, launched by container/web.sh). A static musl binary with
# xterm.js baked into it, so the view needs no network once the image is
# built -- which matters on workshop wifi.
#
# It lives here rather than in Dockerfile.base, where a tool would normally
# go, so that adding the view costs a small code-image layer instead of a
# base rebuild and its multi-gigabyte scanner-database refresh. Move it up to
# the base at the next base refresh. Before the COPY below, so editing a
# lesson does not re-download it.
ARG TTYD_VERSION=1.7.7
RUN arch=$(dpkg --print-architecture) \
    && case "$arch" in amd64) t=x86_64 ;; arm64) t=aarch64 ;; *) echo "unsupported arch: $arch" >&2; exit 1 ;; esac \
    && curl -fsSL -o /usr/local/bin/ttyd \
      "https://github.com/tsl0922/ttyd/releases/download/${TTYD_VERSION}/ttyd.${t}" \
    && chmod +x /usr/local/bin/ttyd \
    && ttyd --version

COPY . /workshop
RUN chmod +x scripts/*.sh scenarios/*/scripts/*.sh investigations/*/scripts/*.sh \
      container/web/start.sh container/web/serve.py

COPY container/motd.txt /etc/workshop-motd
RUN echo 'cat /etc/workshop-motd' >> /root/.bashrc
CMD ["/bin/bash"]
