#!/bin/bash
#
# 01-openedx-installer.sh: build-time installer for Cubite's DigitalOcean
# 1-Click image for the Open edX platform (Ubuntu 24.04, Open edX Verawood,
# Tutor 22.0.2). Packer runs it as root on the build Droplet.
#
# It installs:
#   - OS updates;
#   - Docker Engine 29.x and the Compose v2 plugin from Docker's apt repository
#     for noble, held there by an apt pin (Docker no longer patches 28.x);
#   - Tutor 22.0.2 and its plugins in /opt/tutor/venv, hash-checked;
#   - ufw (configured by 02-ufw-openedx.sh) and unattended-upgrades;
#   - the first-boot script, the setup wizard and the message of the day.
#
# It deliberately runs no Tutor command that creates a config, secrets,
# Docker images or containers. Each Droplet creates its own: images at first
# boot (001_onboot), config and secrets at first root login (openedx-setup).
# The checks at the end fail the build if any of them exist, and a security
# gate at the start fails it if the openedx image would lack known fixes.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
# Keep needrestart from restarting services in the middle of the build.
export NEEDRESTART_SUSPEND=1

TUTOR_VERSION="22.0.2"
TUTOR_VENV="/opt/tutor/venv"
TUTOR_ROOT_DIR="/root/.local/share/tutor"
CUBITE_DIR="/opt/cubite"
IMAGE_ENV="${CUBITE_DIR}/openedx-image.env"
# Docker's apt signing key, as published on docs.docker.com.
DOCKER_KEY_FINGERPRINT="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
APT_OPTS=(-o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold")

log() { printf '\n==> %s\n' "$*"; }
die() { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
# Wait up to 10 minutes for the dpkg lock instead of failing at once.
apt-get() { command apt-get -o DPkg::Lock::Timeout=600 "$@"; }

codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
[ "$codename" = "noble" ] || die "this installer targets Ubuntu 24.04 (noble), found '${codename}'"

# Security gate. The stock overhangio/openedx images of Tutor 22.0.0 to 22.0.2
# lack the release/verawood fixes for GHSA-c6xg-fh3c-vvhh (stored XSS through
# Studio uploads, critical) and GHSA-c6fp-f54c-6cv4 (forum API without
# permission checks). A build with those versions must ship Cubite's patched
# openedx image, pinned by digest in files/opt/cubite/openedx-image.env. The
# digest comes from the summary of the "Patched openedx image" workflow run,
# which checks the image for the fixes before it publishes it. Only a test
# build may skip the gate (packer build -var allow_unpatched_openedx=true), and
# its snapshot name then ends in -UNPATCHED-TEST, so that it is never submitted
# by mistake. First boot and the wizard accept exactly the same pattern.
OPENEDX_IMAGE_PATTERN='^ghcr\.io/amirtds/cubite-openedx@sha256:[0-9a-f]{64}$'
openedx_image=""
if [ -e "$IMAGE_ENV" ]; then
  openedx_image="$(sed -n 's/^OPENEDX_IMAGE=//p' "$IMAGE_ENV" | head -n 1)"
  [[ "$openedx_image" =~ $OPENEDX_IMAGE_PATTERN ]] \
    || die "${IMAGE_ENV} must hold the line OPENEDX_IMAGE=ghcr.io/amirtds/cubite-openedx@sha256:<digest>, copied from the summary of the Patched openedx image workflow run"
fi
case "$TUTOR_VERSION" in
  22.0.0 | 22.0.1 | 22.0.2)
    if [ -n "$openedx_image" ]; then
      log "Security gate: Droplets use the patched openedx image ${openedx_image}"
    elif [ "${CUBITE_ALLOW_UNPATCHED:-false}" = "true" ]; then
      log "Security gate: TEST BUILD with the unpatched stock openedx image. Never submit this snapshot."
    else
      die "security gate: overhangio/openedx:${TUTOR_VERSION} lacks the fixes for GHSA-c6xg-fh3c-vvhh and GHSA-c6fp-f54c-6cv4; bump Tutor to a release that has them, or pin Cubite's patched image in files/opt/cubite/openedx-image.env (test builds only: -var allow_unpatched_openedx=true)"
    fi
    ;;
  *)
    [ -z "$openedx_image" ] \
      || die "${IMAGE_ENV} pins an openedx image built with Tutor 22.0.2, but this build installs Tutor ${TUTOR_VERSION}: delete the file if this release carries the fixes, or build and pin an image for it"
    ;;
esac

# The apt-daily timers can start unattended-upgrades in the middle of the
# build and hold the dpkg lock. Stop them for the rest of this boot only (they
# stay enabled in the image) and wait for any run already in progress.
log "Pausing the apt-daily timers for the rest of the build"
systemctl stop apt-daily.timer apt-daily-upgrade.timer || true
systemd-run --quiet --wait --property="After=apt-daily.service apt-daily-upgrade.service" /bin/true || true

log "Updating the OS"
apt-get -q update
apt-get -y -q "${APT_OPTS[@]}" full-upgrade
apt-get -y -q "${APT_OPTS[@]}" install \
  ca-certificates curl gnupg python3-venv python3-pip libyaml-dev \
  bind9-dnsutils ufw unattended-upgrades

log "Removing conflicting Docker packages, if any"
mapfile -t conflicting < <(
  dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' \
    docker.io docker-compose docker-compose-v2 docker-doc docker-buildx \
    podman-docker containerd runc 2>/dev/null | awk '$1 ~ /^.i/ {print $2}'
)
if [ "${#conflicting[@]}" -gt 0 ]; then
  apt-get -y -q remove "${conflicting[@]}"
fi

log "Configuring Docker: log rotation and the overlay2 image store"
# Container logs are rotated, because a 25 GB disk fills up otherwise. Docker
# 29 uses the containerd image store on fresh installs, which keeps every
# layer twice (compressed and unpacked); the classic overlay2 store, which
# Docker 28 used, keeps one copy.
install -d -m 0755 /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "features": {
    "containerd-snapshotter": false
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

log "Adding Docker's apt repository for ${codename}"
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
gpg_home="$(mktemp -d)"
key_listing="$(GNUPGHOME="$gpg_home" gpg --batch --show-keys --with-colons /etc/apt/keyrings/docker.asc 2>/dev/null || true)"
rm -rf "$gpg_home"
# apt trusts every key in the file, so it must hold Docker's key and no other.
pub_count="$(printf '%s\n' "$key_listing" | grep -c '^pub:' || true)"
[ "$pub_count" = 1 ] \
  || die "Docker's apt key file must hold exactly one key, found ${pub_count}"
key_fingerprint="$(printf '%s\n' "$key_listing" | awk -F: '$1 == "fpr" && !seen { print $10; seen = 1 }')"
[ "$key_fingerprint" = "$DOCKER_KEY_FINGERPRINT" ] \
  || die "Docker's apt key has fingerprint '${key_fingerprint}', expected ${DOCKER_KEY_FINGERPRINT}"
cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

log "Pinning Docker Engine to 29.x and Docker Compose to 2.x"
cat > /etc/apt/preferences.d/cubite-docker <<'EOF'
Explanation: Cubite 1-Click image: hold Docker Engine at 29.x, the line that
Explanation: Docker still patches (28.x gets no more fixes). Revisit at every
Explanation: image rebuild.
Package: docker-ce docker-ce-cli docker-ce-rootless-extras
Pin: version 5:29.*
Pin-Priority: 1001

Explanation: Cubite 1-Click image: hold Docker Compose at 2.x.
Package: docker-compose-plugin
Pin: version 2.*
Pin-Priority: 1001
EOF

log "Installing Docker"
apt-get -q update
apt-get -y -q "${APT_OPTS[@]}" install \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now containerd.service docker.service

docker_ce_version="$(dpkg-query -W -f='${Version}' docker-ce)"
docker_cli_version="$(dpkg-query -W -f='${Version}' docker-ce-cli)"
compose_version="$(docker compose version --short)"
compose_version="${compose_version#v}"
case "$docker_ce_version" in 5:29.*) ;; *) die "docker-ce is ${docker_ce_version}, expected 5:29.x" ;; esac
case "$docker_cli_version" in 5:29.*) ;; *) die "docker-ce-cli is ${docker_cli_version}, expected 5:29.x" ;; esac
case "$compose_version" in 2.*) ;; *) die "Docker Compose is ${compose_version}, expected 2.x" ;; esac
docker_info="$(docker info --format '{{.ServerVersion}} {{.Driver}}')" || die "the Docker daemon is not reachable"
echo "Docker daemon: ${docker_info}"
case "$docker_info" in
  *" overlay2") ;;
  *) die "the Docker daemon reports '${docker_info}', expected the overlay2 storage driver (see /etc/docker/daemon.json)" ;;
esac
docker --version
docker compose version
containerd --version

if [ -n "$openedx_image" ]; then
  log "Checking that Droplets can pull ${openedx_image} without credentials"
  # A throwaway Docker client config: the check runs without a login, like
  # each Droplet's first boot, and leaves nothing in /root/.docker.
  probe_config="$(mktemp -d)"
  if ! env -u DOCKER_AUTH_CONFIG DOCKER_CONFIG="$probe_config" docker manifest inspect "$openedx_image" > /dev/null; then
    rm -rf "$probe_config"
    die "Droplets cannot pull ${openedx_image} without credentials: make the ghcr.io package public, or fix the digest"
  fi
  rm -rf "$probe_config"
fi

log "Installing Tutor ${TUTOR_VERSION} and its plugins in ${TUTOR_VENV}"
for f in requirements-build.txt requirements-tutor.txt; do
  [ -f "${CUBITE_DIR}/${f}" ] || die "${CUBITE_DIR}/${f} is missing (it is uploaded from files/opt/cubite/)"
done
install -d -m 0755 /opt/tutor
python3 -m venv "$TUTOR_VENV"
# Tutor and its plugins are published as source distributions built with
# hatchling. pip does not hash-check the build backend it fetches for isolated
# builds, so the hash-pinned hatchling is installed first and the Tutor
# packages are then built without build isolation.
"${TUTOR_VENV}/bin/pip" install --no-cache-dir --disable-pip-version-check \
  --require-hashes -r "${CUBITE_DIR}/requirements-build.txt"
"${TUTOR_VENV}/bin/pip" install --no-cache-dir --disable-pip-version-check \
  --require-hashes --no-build-isolation --check-build-dependencies \
  -r "${CUBITE_DIR}/requirements-tutor.txt"
ln -sfn "${TUTOR_VENV}/bin/tutor" /usr/local/bin/tutor
ln -sfn "${CUBITE_DIR}/openedx-setup" /usr/local/bin/openedx-setup
ln -sfn "${CUBITE_DIR}/openedx-image-check" /usr/local/bin/openedx-image-check

installed_tutor="$("${TUTOR_VENV}/bin/python" -c 'import importlib.metadata as m; print(m.version("tutor"))')"
[ "$installed_tutor" = "$TUTOR_VERSION" ] || die "installed Tutor is ${installed_tutor}, expected ${TUTOR_VERSION}"
tutor_cli_version="$(HOME=/root /usr/local/bin/tutor --version)"
case "$tutor_cli_version" in
  *"version ${TUTOR_VERSION}") ;;
  *) die "'tutor --version' printed '${tutor_cli_version}', expected version ${TUTOR_VERSION}" ;;
esac
echo "$tutor_cli_version"
"${TUTOR_VENV}/bin/pip" list --disable-pip-version-check --format=freeze | grep -i '^tutor'

log "Enabling unattended security upgrades"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
systemctl enable unattended-upgrades.service

log "Installing the first-boot script, the setup wizard and the message of the day"
# Packer keeps the local file mode, so set the modes here as well.
for f in /etc/update-motd.d/99-one-click \
         /var/lib/cloud/scripts/per-instance/001_onboot \
         "${CUBITE_DIR}/openedx-setup" \
         "${CUBITE_DIR}/openedx-image-check"; do
  [ -f "$f" ] || die "${f} is missing (it is uploaded from files/)"
  chown root:root "$f"
  chmod 0755 "$f"
done
[ -f "${CUBITE_DIR}/tutor-plugins/cubitefixes.yml" ] \
  || die "${CUBITE_DIR}/tutor-plugins/cubitefixes.yml is missing (it is uploaded from files/opt/cubite/)"
chown -R root:root "$CUBITE_DIR"
chmod 0644 "$CUBITE_DIR"/requirements-* "${CUBITE_DIR}/tutor-plugins/cubitefixes.yml"
# Drop Finder metadata in case the build ran from a Mac working tree.
find /etc /opt /var/lib/cloud -name .DS_Store -type f -delete

# Start the wizard on interactive root logins only. Both lines carry the
# marker, and the wizard deletes every line with it once setup completes.
if ! grep -qF 'cubite-openedx-setup' /root/.bashrc; then
  cat >> /root/.bashrc <<'EOF'
# cubite-openedx-setup: start the Open edX setup wizard at interactive root login until setup completes
if [ -t 0 ] && [ -t 1 ] && [ -x /opt/cubite/openedx-setup ]; then /opt/cubite/openedx-setup; fi # cubite-openedx-setup
EOF
fi

log "Removing the DigitalOcean agent, if present"
agent_status="$(dpkg-query -W -f='${db:Status-Abbrev}' droplet-agent 2>/dev/null || true)"
case "$agent_status" in
  ?i*) apt-get -y -q purge droplet-agent ;;
esac
rm -rf /opt/digitalocean

apt-get -y -q clean

log "Checking that the image holds no Tutor config, secrets, per-Droplet state, Docker images or containers"
[ ! -e "${TUTOR_ROOT_DIR}/config.yml" ] \
  || die "${TUTOR_ROOT_DIR}/config.yml exists: the image must not contain a Tutor config or secrets"
if [ -d "$TUTOR_ROOT_DIR" ]; then
  rmdir "$TUTOR_ROOT_DIR" 2>/dev/null || die "${TUTOR_ROOT_DIR} is not empty: the image must not contain Tutor state"
fi
# A setup.done in the state directory would skip the wizard on every Droplet.
for p in /var/lib/cubite-openedx /var/log/cubite-openedx /root/.digitalocean_password \
         /swapfile /root/.local/share/tutor-plugins; do
  [ ! -e "$p" ] || die "${p} exists: per-Droplet state must not be in the image"
done
# Each listing is captured first, so that an unreachable daemon fails the
# build instead of passing as an empty list.
docker_images="$(docker images -aq)" || die "the Docker daemon is not reachable"
[ -z "$docker_images" ] || die "Docker images exist: the image must not contain any"
docker_containers="$(docker ps -aq)" || die "the Docker daemon is not reachable"
[ -z "$docker_containers" ] || die "Docker containers exist: the image must not contain any"
docker_volumes="$(docker volume ls -q)" || die "the Docker daemon is not reachable"
[ -z "$docker_volumes" ] || die "Docker volumes exist: the image must not contain any"

# dockerd wrote its engine ID when it first started. Without the file, each
# Droplet's dockerd creates its own at first boot.
log "Stopping Docker and removing its engine ID"
systemctl stop docker.service docker.socket containerd.service
rm -f /var/lib/docker/engine-id
# The test plan compares this with a test Droplet's /etc/machine-id.
log "Build Droplet machine-id: $(cat /etc/machine-id 2>/dev/null || true)"

log "Installed: docker-ce ${docker_ce_version}, Docker Compose ${compose_version}, Tutor ${installed_tutor}"
