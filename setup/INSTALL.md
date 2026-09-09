---
id: setup-install
oneliner: "Copy-paste installation commands for macOS and Linux, Podman setup, and binary verification checks."
track: reference
---

# Installation Transcripts

Detailed installation and environment configuration commands corresponding to [`02 tools.md`](./02%20tools.md). Run `./scripts/tools-check.sh` to determine missing packages.

## macOS (Homebrew)

### Core Development and Analysis Tools

```command
brew install \
  openjdk@21 \
  maven \
  node \
  python \
  jq \
  syft \
  grype \
  trivy \
  cosign \
  pipx
```

Verify installations:

```command
java -version
javac -version
mvn --version

node --version
npm --version

python3 --version
python3 -m pip --version
```

### pip-audit

```command
pipx ensurepath
pipx install pip-audit
pip-audit --version
```

### GuardDog

```command
pipx install guarddog
guarddog --version
```

### Snyk CLI

```command
npm install -g snyk
snyk --version
```

See [`03 ACCOUNTS-AND-KEYS.md`](./03%20ACCOUNTS-AND-KEYS.md) for authentication.

### Docker

Install Docker Desktop.

Verify:

```command
docker version
docker scout version
```

## Linux (Debian / Ubuntu APT)

### Base Utilities

```command
sudo apt-get update

sudo apt-get install -y \
  git \
  curl \
  jq \
  zip \
  unzip \
  tar \
  python3 \
  python3-pip \
  python3-venv \
  pipx
```

### JDK 21

Install a JDK 21 distribution (such as `temurin-21-jdk` from Adoptium).

Verify:

```command
java -version
javac -version
```

### Maven

```command
sudo apt-get install -y maven
mvn --version
```

Maven 3.9+ is required.

### Node.js

Node.js 20+ is required. Installation via `nvm`:

```command
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.6/install.sh | bash
. "$HOME/.nvm/nvm.sh"

nvm install 24
```

Verify:

```command
node --version
npm --version
```

### pip-audit

```command
pipx ensurepath
pipx install pip-audit
pip-audit --version
```

### GuardDog

```command
pipx install guarddog
guarddog --version
```

### Syft

```command
curl -sSfL https://get.anchore.io/syft \
  | sudo sh -s -- -b /usr/local/bin

syft version
```

### Grype

```command
curl -sSfL https://get.anchore.io/grype \
  | sudo sh -s -- -b /usr/local/bin

grype version
```

### cosign

```command
COSIGN_VERSION=3.1.3
sudo curl -fsSL -o /usr/local/bin/cosign \
  "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-$(dpkg --print-architecture)"
sudo chmod +x /usr/local/bin/cosign

cosign version
```

### Trivy

Install Trivy from the Aqua Security package repository.

Verify:

```command
trivy --version
```

### Snyk CLI

```command
npm install -g snyk
snyk --version
```

### Docker

Install Docker Engine or Docker Desktop for Linux.

Verify:

```command
docker version
docker scout version
```

## Podman Configuration

Podman compatibility is limited to scenarios S01/S02 container builds. See constraints in [`02 tools.md`](./02%20tools.md).

### macOS

```command
brew install podman
podman machine init
podman machine start
podman info
```

### Debian / Ubuntu

```command
sudo apt-get update
sudo apt-get install -y podman
podman info
```

## Manual Verification Matrix

Automated verification is provided by `./scripts/tools-check.sh`. Manual validation equivalents:

```command
git --version
bash --version

java -version
javac -version
mvn --version

node --version
npm --version

python3 --version
python3 -m pip --version

jq --version
curl --version
zip -v
unzip -v
tar --version

docker version
docker scout version

syft version
snyk --version
trivy --version
grype version
pip-audit --version
cosign version
guarddog --version
```

For T06:

```command
printenv NVD_API_KEY >/dev/null && \
  echo "NVD API key: configured" || \
  echo "NVD API key: not configured"
```
