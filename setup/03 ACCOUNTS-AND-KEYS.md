---
id: setup-accounts-and-keys
oneliner: "Authentication configuration, API keys, and external endpoint access requirements."
track: core
---

# Accounts and API Keys

Configuration instructions for investigations requiring authenticated API endpoints and registry access.

## Snyk Authentication (T01)

T01 requires an authenticated Snyk CLI session (free tier account is sufficient):

```command
snyk auth
```

Verify authentication status:

```command
snyk --version
snyk config get api
```

## NVD API Key (T06)

T06 executes the OWASP Dependency-Check Maven Plugin. The test harness dynamically selects the plugin version based on key availability:

```text
NVD_API_KEY present  -> Dependency-Check 13.0.0 (uses NVD 2.0 API with elevated rate limits)
NVD_API_KEY absent   -> Dependency-Check 12.2.2 (fallback version avoiding key-required API paths)
```

### Request an NVD API Key

1. Navigate to <https://nvd.nist.gov/developers/request-an-api-key>.
2. Complete the registration form and accept the Terms of Use.
3. Activate the key using the confirmation link sent by NIST (valid for 7 days).
4. Store the API key in a secure local credentials store.

### Export Environment Variable

```command
export NVD_API_KEY='your-api-key'
```

Verify the variable is set:

```command
printenv NVD_API_KEY >/dev/null && echo "NVD_API_KEY is exported"
```

When executing `./scripts/run-dependency-check-s04.sh`, the script logs:

```text
NVD API key: supplied via NVD_API_KEY environment variable
```

## Docker Registry Authentication (T02)

Docker Scout requires an authenticated Docker CLI session:

```command
docker login
docker scout version
```

## npm Registry Verification (T07)

T07 requires outbound connectivity to the public npm registry:

```command
npm config get registry
```

Expected output:

```text
https://registry.npmjs.org/
```

## Network Endpoint Requirements

The build and scanner harnesses require outbound TCP/HTTPS (port 443) access to the following endpoints:

```text
repo.maven.apache.org
registry.npmjs.org
registry-1.docker.io
api.snyk.io
nvd.nist.gov
cisa.gov
github.com
api.github.com
raw.githubusercontent.com
pypi.org
```

Environments utilizing SSL interception proxies or custom CA certificates must configure the corresponding CA trust stores for Java (`cacerts`), Node.js (`NODE_EXTRA_CA_CERTS`), and Python (`REQUESTS_CA_BUNDLE`).
