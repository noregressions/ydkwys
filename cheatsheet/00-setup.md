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

### House Keeping

Every `run.sh` has a matching `stop.sh`, and `run.sh` refuses to start if an preclaimed
port is already busy. 

```command
lsof -nP -iTCP:8082 -sTCP:LISTEN
kill <PID>
```
