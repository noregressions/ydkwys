---
id: cheatsheet-setup
oneliner: "Part 1 and the setup behind it: what to run to get a working machine, the route in order, and where each stop lives in this book."
track: reference
---

# Part 1 — Start Here

## Setup

Clone <{{ vars.repoUrl }}>  then pick a route

#### Run Locally 

Run tools-check to assess what tools your missing to run locally.
```command
./scripts/tools-check.sh
```

Build all demos, samples and containers. Takes time!
```command
./scripts/build-all.sh
```

#### Existing Container Mode

We have an image on DockerHub that has all the tools and samples installed and everything built. It's quite large.
```command
./container/run.sh
```

Or build the image locally first, then run the image you built.
```command
./container/build.sh
WORKSHOP_IMAGE=shipping-workshop:latest ./container/run.sh
```

#### Browser View

Instructions and a shell side by side in the browser, in the same container
`run.sh` uses. Needs a locally built image; the published one predates it.
```command
WORKSHOP_IMAGE=shipping-workshop:latest ./container/web.sh
```

Opens `http://localhost:7680`. Browse the book at
`http://localhost:7680/site/index.html` and press **Open with terminal** on any
page to get that page beside a shell. A second tab on `http://localhost:7681`
is a second, independent shell — which is what S03/S04/S05 want, one shell for
the server and one for the `curl`. `Ctrl-C` stops it.

Move the ports if something already holds them.
```command
WEB_PORT=9000 TTYD_PORT=9001 ./container/web.sh
```

### House Keeping

Every `run.sh` has a matching `stop.sh`, and `run.sh` refuses to start if an preclaimed
port is already busy. 

```command
lsof -nP -iTCP:8082 -sTCP:LISTEN
kill <PID>
```
