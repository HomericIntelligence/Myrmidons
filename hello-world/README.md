# hello-world

Pull-based myrmidon E2E test worker. Connects to NATS JetStream, pulls tasks
from `hi.myrmidon.hello.>`, processes them, and publishes completion events back
to the HomericIntelligence mesh.

## Prerequisites

| Tool | Minimum version | Notes |
|------|----------------|-------|
| cmake | ≥ 3.20 | Build system generator |
| ninja | any | Build backend (`-G Ninja`) |
| g++ or clang++ | g++ ≥ 10 / clang++ ≥ 12 | C++20 support required |
| libssl-dev / openssl | any | Required by nats.c (fetched via FetchContent) |
| git | any | FetchContent clones nats.c and nlohmann/json at configure time |

### Install by platform

**Ubuntu / Debian**

```bash
sudo apt-get update
sudo apt-get install -y cmake ninja-build g++ libssl-dev git
```

**macOS (Homebrew)**

```bash
brew install cmake ninja openssl git
```

**Windows (winget)**

```powershell
winget install Kitware.CMake Ninja-build.Ninja Git.Git
# OpenSSL: download the Win32/Win64 installer from slproweb.com or use vcpkg
```

> Windows support is less tested. A Linux build environment (WSL2 or Docker) is
> the recommended path on Windows.

## Build

**Primary (requires `just`)** — run from the repository root:

```bash
just build-hello-world
```

**Fallback (no `just` needed)** — run from the repository root:

```bash
cmake -S hello-world -B build/hello-world -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/hello-world
```

The configure step fetches `nats.c v3.12.0` and `nlohmann/json v3.11.3` from
GitHub. An internet connection is required on first build; subsequent builds use
the CMake cache.

## Run

```bash
# Default: connects to nats://localhost:4222
./build/hello-world/hello_myrmidon

# Custom NATS URL
NATS_URL=nats://my-server:4222 ./build/hello-world/hello_myrmidon
```

You need a running NATS server with JetStream enabled. The binary creates the
required streams (`homeric-myrmidon`, `homeric-tasks`, `homeric-logs`) on
startup if they do not exist.

## Docker

A `Dockerfile` is included for containerised builds:

```bash
docker build -t hello-myrmidon hello-world/
docker run --rm -e NATS_URL=nats://host.docker.internal:4222 hello-myrmidon
```
