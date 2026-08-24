# dev-images

Container images and distrobox definitions for the `dev` and `devj` containers on
Fedora Silverblue.

## Layout

```
dev-images/
├── common/Containerfile   →  localhost/dev-common   (shared base, image only)
├── dev/Containerfile      →  localhost/dev          (general dev toolchain)
├── devj/Containerfile     →  localhost/devj         (dev + Java)
├── distrobox.ini          →  declarative distrobox manifest ([dev], [devj])
├── build.sh               →  incremental build + create containers
├── rebuild.sh             →  forced no-cache build + replace containers
└── README.md
```

## Image chain

Each image layers on the previous one, so storage is deduplicated (devj shares
all of dev's layers; only the Java layer is extra).

| Image | FROM | Adds |
|---|---|---|
| `localhost/dev-common:latest` | `fedora-toolbox:44` | `vim-enhanced`, `wl-clipboard`, `vi -> vim` link |
| `localhost/dev:latest` | `localhost/dev-common:latest` | `nodejs20`, `uv`, `golang`, bun (`/usr/local/bin`), uv Python 3.11 + 3.13 |
| `localhost/devj:latest` | `localhost/dev:latest` | `java-latest-openjdk-devel` |

Notes:
- `dev-common` is an image-only intermediate — no distrobox, no ini section.
- Tools are baked into the image layers (container-only paths like
  `/usr/local/bin/bun` and `/usr/local/share/uv-python`), so nothing leaks into
  the host filesystem, and starts are fast (no per-start downloads).
- Layer caching: rebuilding an unchanged Containerfile is near-instant
  (`podman build` reuses cached layers). Editing a `RUN` line invalidates that
  layer and everything after it.

## Containers

Managed declaratively via `distrobox.ini`:

| Section | Image | Volume |
|---|---|---|
| `[dev]` | `localhost/dev:latest` | `/home/linuxbrew:/home/linuxbrew` |
| `[devj]` | `localhost/devj:latest` | `/home/linuxbrew:/home/linuxbrew` |

`dev` has no Java; `devj` is `dev` plus Java 26.

## Usage

```bash
# Build images (incremental) and create containers if missing
./build.sh

# Force a full no-cache rebuild and replace both containers
./rebuild.sh

# Enter a container
distrobox enter dev
distrobox enter devj

# Regenerate containers from the manifest (no image rebuild)
distrobox assemble create --file ~/Devel/dev-images/distrobox.ini
# ...or replace them:
distrobox assemble create --replace --file ~/Devel/dev-images/distrobox.ini
```

Manual equivalents (what the scripts run):

```bash
podman build -t localhost/dev-common:latest ~/Devel/dev-images/common
podman build -t localhost/dev:latest      ~/Devel/dev-images/dev
podman build -t localhost/devj:latest     ~/Devel/dev-images/devj

distrobox create --name dev  --image localhost/dev:latest  --volume /home/linuxbrew:/home/linuxbrew
distrobox create --name devj --image localhost/devj:latest --volume /home/linuxbrew:/home/linuxbrew
```

## Adding / removing tools

- **Ad-hoc** (no rebuild): `distrobox enter dev` then `dnf install <pkg>` — lands
  in the container's writable layer; lost if the container is recreated.
- **Declared**: edit the relevant `Containerfile` `dnf install` line, then
  `./build.sh` (or `./rebuild.sh`) to bake it into the image.

## uv Python install dir permission

`uv` is pointed at the container-local path via
`ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv-python`, so `uv python install`
writes into the image layer instead of the host-mounted `$HOME`.

Because that path is baked into the image (and `uv python install` runs as
**root** during the build), the directory ends up **root-owned**. At runtime the
container runs as the host user (`andy`, uid/gid 1000), so any later
`uv python install <ver>` (e.g. the free-threaded `3.14t`) fails with:

```
error: Failed to create Python minor version link directory
  Caused by: Permission denied (os error 13)
```

The fix is baked into the `dev/Containerfile`: after installing the baked-in
Pythons, `chown -R 1000:1000 /usr/local/share/uv-python` makes the directory
writable by the runtime user. Use the **numeric uid/gid** here, not the
`andy` username, because the distrobox user is created at runtime and does not
exist in `/etc/passwd` during the image build.

The `3.14t` free-threaded Python is deliberately *not* baked in — it's used as
a runtime test to confirm a fresh `uv python install` succeeds inside the
container after recreation.

## Why Containerfile instead of ini hooks

The original approach ran `additional_packages` / `init_hooks` per container,
which wrote tools into `$HOME` — a directory bind-mounted from the host — so
installs (bun, uv Pythons) leaked into `/var/home/andy` and had to be
re-downloaded on every container start. Baking everything into the image at
build time keeps tools in the image layer, avoids the host leak, and makes
starts near-instant.
