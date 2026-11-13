# Cubite's DigitalOcean 1-Click image for the Open edX® platform

Cubite's 1-Click image for DigitalOcean installs the Open edX platform (Verawood) with Tutor on Ubuntu 24.04. Maintained by Cubite ([cubite.io](https://cubite.io/open-edx?utm_source=github-1click)), which also runs the Open edX platform as a managed service from $1,260 a month.

**Supported versions:** Open edX Verawood (`release/verawood.2`, from Tutor's stock images), Tutor 22.0.4, Docker Engine 29.x with Docker Compose 2.x, Ubuntu 24.04 LTS.
**Last tested on a Droplet:** 2026-11-12, this code (Tutor 22.0.4 with Tutor's stock images; snapshot `cubite-openedx-verawood-tutor22-2404-20261112-2302`, nyc3, s-4vcpu-8gb): first boot (4 min), setup with a Let's Encrypt certificate (40 min), the stock-image checks (`release/verawood.2` at 484f080fa0, openedx-forum 0.4.2.post1, no cubitefixes, the `studio_library_content` search index), course assets served with `Content-Security-Policy: sandbox`, the admin password and a reboot (the platform back in 55 s) all passed. The in-place upgrade of a Droplet created from version 13 of the live listing (Tutor 22.0.2 with Cubite's patched image) also passed: the documented commands moved it to Tutor 22.0.4 and its stock images in a 9-minute launch, with the demo course and the admin account kept.

This repository holds the Packer template and the scripts that build the image behind Cubite's listing on the DigitalOcean Marketplace (draft title in [listing/title.txt](listing/title.txt)). Cubite builds and supports the image. DigitalOcean does not build or support it.

## What the image contains

- Ubuntu 24.04 with all updates applied at build time, and unattended security upgrades turned on.
- Docker Engine 29.x and the Docker Compose 2.x plugin from Docker's signed apt repository, held at those versions by an apt pin (`/etc/apt/preferences.d/cubite-docker`). Docker no longer patches 28.x: 29.8.2 and later fix registry and image-pull vulnerabilities that every Droplet's first boot would otherwise be exposed to. Tutor needs Docker 24.0.5 or later and Compose 2.
- `/etc/docker/daemon.json` with log rotation (json-file, 10 MB, 3 files), because a 25 GB disk fills up otherwise, and with the containerd image store turned off (`"containerd-snapshotter": false`). Docker 29 would use that store on a fresh install, and it keeps every image layer twice (compressed and unpacked); the classic overlay2 store, which Docker 28 used, keeps one copy. The installer fails the build unless the daemon reports overlay2.
- Tutor 22.0.4 and every plugin in its `[full]` extra (among them tutor-mfe 22.1.2, the first whose MFE images are built from Verawood.2), in a virtual environment at `/opt/tutor/venv`, installed with `pip --require-hashes` from [files/opt/cubite/requirements-tutor.txt](files/opt/cubite/requirements-tutor.txt). Tutor's packages are source distributions built with hatchling, so the hash-pinned hatchling from [requirements-build.txt](files/opt/cubite/requirements-build.txt) is installed first and the Tutor packages are built without build isolation. That keeps every downloaded file hash-checked.
- A firewall (ufw) that allows only 22 (rate-limited), 80 and 443.
- The first-boot script, the setup wizard, the message of the day and `openedx-image-check`, described below.

## What it deliberately does not contain

- **No Docker images.** Each Droplet downloads Tutor's stock images at first boot (for example `overhangio/openedx:22.0.4-indigo`, built from `release/verawood.2`), so the snapshot stays small and never ships stale images.
- **No Tutor configuration and no secrets.** Tutor generates the MySQL, Django, JWT, OAuth and Meilisearch secrets the first time its configuration is saved. That happens on each Droplet, in the setup wizard, so no two Droplets share them. The installer fails the build if a `config.yml`, a Docker image, a container or a volume exists, or any per-Droplet state (`/var/lib/cubite-openedx`, `/var/log/cubite-openedx`, `/root/.digitalocean_password`, `/swapfile`, `/root/.local/share/tutor-plugins`). It also removes Docker's engine ID, so that each Droplet's Docker creates its own.
- **No default admin account.** The wizard creates one with a random password.
- **No telemetry.** Nothing reports back to Cubite. The bundled Meilisearch sends anonymous usage analytics unless told not to, so the wizard sets `MEILI_NO_ANALYTICS=true` in `/root/.local/share/tutor/env/local/docker-compose.override.yml` (the override file Tutor documents for local changes). Tutor keeps that file across `tutor config save`, but `tutor config save --clean` deletes it; delete it yourself if you set `RUN_MEILISEARCH=false`. To check DNS, the wizard asks DigitalOcean's metadata service for the Droplet's own IP addresses and the public resolvers 1.1.1.1 and 8.8.8.8 for the domain's records.

## How a Droplet sets itself up

1. **First boot.** cloud-init runs [`/var/lib/cloud/scripts/per-instance/001_onboot`](files/var/lib/cloud/scripts/per-instance/001_onboot) once per Droplet. It pulls the platform images (`tutor images pull openedx permissions mfe caddy meilisearch mongodb mysql redis smtp`) with three tries, each with a time limit (20 minutes for the separate pull of a patched openedx image, on an image that pins one, and 30 for `tutor images pull`), writes `ok` or `pull-failed` to `/var/lib/cubite-openedx/firstboot.status`, logs only to `/var/log/cubite-openedx/firstboot.log` (mode 0600) and always exits 0. It creates no configuration and no secrets. SSH stays open the whole time.
2. **First root login.** A line in `/root/.bashrc` starts [`openedx-setup`](files/opt/cubite/openedx-setup) in interactive shells only. The wizard:
   - takes a lock, so a second SSH session cannot run it twice;
   - waits up to 45 minutes for first boot to finish;
   - refuses to continue below about 3.5 GiB of memory, and on 4 GB Droplets adds a 2 GiB swap file and uses one uWSGI worker each for the LMS and Studio;
   - asks for the LMS domain (88 characters at most, because the platform stores `studio.<domain>:8001` in a 100-character column), the platform name and the admin email, and validates them;
   - asks the public resolvers 1.1.1.1 and 8.8.8.8 (not `/etc/hosts`, where cloud-init maps the Droplet's own name to 127.0.1.1) whether the domain, `studio.`, `apps.` and `meilisearch.` under it all point at the Droplet, and whether any AAAA record points elsewhere, and prints the A record and wildcard CNAME to create when they do not;
   - runs `tutor config save --set LMS_HOST=... --set CMS_HOST=studio.<domain> --set ENABLE_HTTPS=true --set PLATFORM_NAME=... --set CONTACT_EMAIL=...` (plus `DOCKER_IMAGE_OPENEDX` when the image pins Cubite's patched openedx image, which none has done since Tutor 22.0.4), which generates this Droplet's secrets, then `tutor plugins enable forum` (and, with a patched image, installs and enables the cubitefixes plugin). The wizard keeps its own files root-only (umask 077) but runs Tutor with umask 022, because Tutor's env files are bind-mounted into containers that run as uid 1000; it then makes `config.yml` mode 0600 and the env tree readable, and writes the Meilisearch override above;
   - runs `tutor local launch --non-interactive` in a session of its own, so that a dropped SSH connection or Ctrl-C cannot stop it in the middle of the database migrations. All of its output goes to `/var/log/cubite-openedx/setup.log` (mode 0600), because Tutor echoes commands that contain passwords; the wizard follows that log to show progress;
   - creates the `admin` user with a random password saved in `/root/.digitalocean_password` (mode 0600);
   - waits for the Let's Encrypt certificate, writes a plain-text summary, marks setup as done and removes its line from `/root/.bashrc`.

   Every step is safe to repeat. If the wizard is interrupted or fails, it starts again at the next root login, or run `openedx-setup`.
3. **After setup.** The message of the day ([`99-one-click`](files/etc/update-motd.d/99-one-click)) shows the saved summary. Containers restart after a reboot.

## What buyers need

- **A Droplet with enough memory:** 8 GB / 4 vCPUs, the tested size; 4 GB / 2 vCPUs is the untested minimum. The image's minimum disk is 25 GB, so DigitalOcean also offers 1 GB and 2 GB plans; the wizard refuses them, because the platform's database migrations fail with less than 4 GB.
- **A domain name:** an A record for the LMS domain and a wildcard CNAME (`*.learn.example.com` to `learn.example.com`), both DNS only (not proxied), and no AAAA record unless it points at the Droplet's own IPv6 address. Nothing answers on the bare IP address until setup has run.
- **An SMTP provider:** DigitalOcean blocks ports 25, 465 and 587, so account activation, password reset and the notification emails Verawood turns on by default need an external provider on another port:
  `tutor config save --set RUN_SMTP=false --set SMTP_HOST=... --set SMTP_PORT=... --set SMTP_USERNAME=... --set SMTP_PASSWORD=... --set SMTP_USE_TLS=true`, then `tutor local launch -I`.

Tutor prints an alert that running it as root is "strongly not recommended". On this single-purpose Droplet, running it as root is a deliberate choice: the Docker group would grant the same rights.

## Building the image

You need Packer 1.10 or later (1.16.x recommended), with network access to download the DigitalOcean plugin, and a DigitalOcean API token for the team that owns the Marketplace listing. Snapshots made with another team's token do not show in the Vendor Portal. Set only `DIGITALOCEAN_TOKEN` in the environment. Never pass the token with `-var` (it ends up in the shell history and `ps` output) or in a `.pkrvars.hcl` file, and never write it into a file in this repository: `*.pkrvars.hcl` and `manifest.json` are git-ignored.

Before every build:

1. **Check the security gate.** Look for new Tutor 22.0.x releases and new Open edX security advisories. If a release fixes something the pinned versions lack, bump the pins. The November 2026 build runs Tutor 22.0.4 with Tutor's stock images: Tutor 22.0.4 builds `release/verawood.2`, which has the fixes for the five edx-platform advisories of 2026-10-29 (two of them critical: GHSA-2vm4-4f35-jgpv and GHSA-hh7c-hrv9-6qw9) and the three fixes that version 13's patched openedx image cherry-picked. The installer enforces this in `scripts/01-openedx-installer.sh`: it fails the build with any Tutor release older than `MIN_TUTOR_VERSION` (22.0.4; Tutor 22.0.0 to 22.0.3 build `release/verawood.1`), and while `files/opt/cubite/openedx-image.env` exists it fails unless the release is listed in `PATCHED_IMAGE_RELEASES` (empty today). Raise `MIN_TUTOR_VERSION` when a Tutor release is the first with a fix that matters. If the newest release still lacks one, bring back Cubite's patched openedx image (see Security): list the release in `PATCHED_IMAGE_RELEASES` and pin the image in `files/opt/cubite/openedx-image.env`; the gate then fails the build unless that file pins `ghcr.io/amirtds/cubite-openedx` by digest and the digest can be pulled without credentials. It cannot tell a patched digest from another one: the workflow's image check establishes that, so copy the digest only from the summary of a successful run. A test build can skip the gate with `packer build -var allow_unpatched_openedx=true marketplace.pkr.hcl`; its snapshot name then ends in `-UNPATCHED-TEST`, and such a snapshot must never be submitted. When a Tutor release with the fixes ships, bump the pins, delete `files/opt/cubite/openedx-image.env` and empty the list again.
2. **Re-generate the hash-pinned requirements in a python:3.12 Linux container**, so the hashes match what the Linux build installs:

   ```bash
   docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src python:3.12 sh -c '
     pip install pip-tools==7.6.2 &&
     pip-compile --generate-hashes --allow-unsafe --strip-extras \
       --output-file=files/opt/cubite/requirements-tutor.txt files/opt/cubite/requirements-tutor.in &&
     pip-compile --generate-hashes --allow-unsafe --strip-extras \
       --output-file=files/opt/cubite/requirements-build.txt files/opt/cubite/requirements-build.in &&
     python -m venv /tmp/v &&
     /tmp/v/bin/pip install --require-hashes -r files/opt/cubite/requirements-build.txt &&
     /tmp/v/bin/pip install --require-hashes --no-build-isolation --check-build-dependencies \
       -r files/opt/cubite/requirements-tutor.txt &&
     /tmp/v/bin/tutor --version'
   ```

   It must print `tutor, version 22.0.4`. Review the diff before committing. Then check the lock with the Python and pip that the image uses (Ubuntu 24.04's Python 3.12.3 and pip 24.0, whose `--no-build-isolation` and `--check-build-dependencies` behaviour the build relies on):

   ```bash
   docker run --rm --platform linux/amd64 -v "$PWD":/src -w /src ubuntu:24.04 sh -c '
     apt-get update && apt-get install -y python3-venv &&
     python3 -m venv /tmp/v &&
     /tmp/v/bin/pip install --require-hashes -r files/opt/cubite/requirements-build.txt &&
     /tmp/v/bin/pip install --require-hashes --no-build-isolation --check-build-dependencies \
       -r files/opt/cubite/requirements-tutor.txt &&
     /tmp/v/bin/tutor --version'
   ```

   It must also print `tutor, version 22.0.4`.
3. **Run the static checks:** `packer init .`, `packer fmt -check .`, `DIGITALOCEAN_TOKEN=placeholder-not-a-token packer validate .`, `bash -n` and `shellcheck` on every script, and `git ls-files -s scripts files` (every script must be mode 100755).

Build:

```bash
export DIGITALOCEAN_TOKEN=...   # from your password manager, never from a file in this repository
packer init .
packer build marketplace.pkr.hcl
```

The build creates a temporary `s-1vcpu-1gb` Droplet in the build region (`tor1` unless you pass `-var region=<slug>`; DigitalOcean's basic sizes come and go by region for this account, so check `GET /v2/sizes` first) named `cubite-openedx-build-YYYYMMDD-hhmm` (without the DigitalOcean agent), uploads `files/etc`, `files/opt` and `files/var`, runs `scripts/01-openedx-installer.sh`, `02-ufw-openedx.sh` and DigitalOcean's `90-cleanup.sh`, stops rsyslog and empties the top-level log files in `/var/log` (the image check warns about any larger than 50 bytes), and finally runs DigitalOcean's `99-img-check.sh`, then takes the snapshot `cubite-openedx-verawood-tutor22-2404-YYYYMMDD-hhmm` (UTC, with `-UNPATCHED-TEST` appended for a test build of the unpatched stock image) and deletes the Droplet. `manifest.json` records the snapshot ID. A `[FAIL]` from the image check, or any failed assertion in the installer, fails the build. The first step accepts exit code 2 from `cloud-init status --wait`, which it returns when cloud-init finished with recoverable errors (DigitalOcean's marketplace-partners issue 186).

## Testing a build

Create an `s-4vcpu-8gb` Droplet in the build region from the snapshot with a throwaway SSH key, then:

- name the test Droplet after its LMS domain (for example `learn.example.com`), so that cloud-init maps that name to 127.0.1.1 in `/etc/hosts` and the wizard's DNS check is tested against it;
- before logging in interactively, check over non-interactive SSH: no `/root/.local/share/tutor/config.yml`, no `/opt/digitalocean` from the image (DigitalOcean installs its droplet agent into each new Droplet, so a directory dated after the Droplet's creation is expected), `ufw status` shows only 22, 80 and 443, `firstboot.status` is `ok` and `firstboot.log` is mode 0600;
- check that `docker info --format '{{.ServerVersion}} {{.Driver}}'` prints 29.x and `overlay2`, and that `/etc/machine-id` differs from the one the build log printed. If they match, empty `/etc/machine-id` at the end of the installer (Ubuntu cloud images ship it empty), rebuild, and check that docker, ufw and unattended-upgrades are still enabled after first boot;
- log in before DNS exists: the message of the day appears, the wizard rejects a bad domain, fails the DNS check and prints the records, and comes back at the next login;
- add the A and wildcard CNAME records, run the wizard with the platform name `Acme: Learning`, and check `tutor config printvalue PLATFORM_NAME`. While the launch runs, close the SSH connection; log in again, check with `tail /var/log/cubite-openedx/setup.log` that the launch went on to the end, then run `openedx-setup` to complete setup;
- check that the Droplet runs Tutor's stock images: `/opt/cubite/openedx-image.env` does not exist, `tutor config printvalue DOCKER_IMAGE_OPENEDX` and `docker inspect -f '{{.Config.Image}}' tutor_local-lms-1` print `docker.io/overhangio/openedx:22.0.4-indigo`, `tutor config printvalue MFE_DOCKER_IMAGE` prints `docker.io/overhangio/openedx-mfe:22.1.2-indigo`, `tutor local exec lms git rev-parse HEAD` prints 484f080fa0cf55d164d2647bf6fa348885128f5d (`release/verawood.2`), `tutor local exec lms pip show openedx-forum` reports 0.4.2.post1 or later, `tutor plugins list` does not show cubitefixes enabled, and `openedx-image-check` says the Droplet already uses Tutor's own image. After `tutor local do importdemocourse`, a course asset (for example the course image) is served with `Content-Security-Policy: sandbox` (the demo course's JavaScript sample problem then no longer runs, as expected), and a content library created in Studio shows up in Studio's library search;
- check that `stat -c %a /root/.local/share/tutor/env/apps/openedx/settings/lms/production.py` prints 644, `stat -c %a /root/.local/share/tutor/config.yml` prints 600, and `tutor local exec meilisearch env` shows `MEILI_NO_ANALYTICS=true`;
- check HTTPS on the LMS, `studio.`, `apps.` and `meilisearch.` names, sign in to the LMS and Studio, create a course, enrol a learner, post in a discussion, and run `tutor local do tests smoke`;
- check `tutor local logs --tail 300 mysql mongodb redis meilisearch` for errors about open files: Docker 29 starts containers with a soft limit of 1024 open files, where Docker 28 allowed 1048576;
- check that the MySQL root password from `config.yml` does not appear in `/var/log/cloud-init-output.log`, and that a reboot brings everything back without the wizard;
- test the in-place upgrade of a Droplet created from the previous version of the image: set one up from the live listing, import the demo course, then follow Keeping a Droplet up to date. `openedx-image-check` must report that it moved the Droplet back to Tutor's own image and disabled the cubitefixes plugin; after the launch, run the stock-image checks above and check that the demo course and the admin account are still there;
- destroy the test Droplets and remove the DNS records.

Record the first-boot and launch times for the listing's getting-started text.

## Submitting to the Marketplace

Before submitting, fill in every placeholder. This must print nothing (the patterns are written so that they do not match this line):

```bash
grep -rnE 'T[B]D|GITHUB_[H]OME|\[[y]yyy\]' listing README.md SECURITY.md LICENSE
```

The title uses the ® sign, as the Open edX trademark policy asks for the first and most prominent use. If the Vendor Portal rejects the character, use the title without the platform name (for example `Cubite`), and keep the mark with ® in the summary.

In the Vendor Portal (cloud.digitalocean.com/vendorportal), open the listing, select the tested snapshot (it leaves your account when you submit), paste the texts from [listing/](listing/), add the reason for the update, tick the acknowledgements and submit everything in one submission. A listing that is pending or in review cannot be updated.

The `listing/` folder holds the drafts: [title.txt](listing/title.txt), [summary.txt](listing/summary.txt), [description.md](listing/description.md), [getting-started.md](listing/getting-started.md) and [software-included.json](listing/software-included.json) (the version label, the OS and the software list, in the shape of the Vendor API's update request).

## Keeping a Droplet up to date

- **Ubuntu security updates** install automatically (unattended-upgrades). Docker comes from Docker's repository, so update it with `apt-get update && apt-get upgrade`; the pin keeps it on 29.x and Compose on 2.x.
- **Tutor 22.0.x patch releases** do not need a new Droplet image. Back up `/root/.local/share/tutor` first, then run `/opt/tutor/venv/bin/pip install --upgrade --upgrade-strategy eager "tutor[full]>=22.0.4,<23.0.0"`, `openedx-image-check` and `tutor local launch -I`. `--upgrade-strategy eager` upgrades the plugins as well: without it, pip keeps every plugin that still satisfies `tutor[full]`, and Tutor 22.0.4 needs tutor-mfe 22.1.2, whose MFE image is built from Verawood.2 (with an older one, Studio's library search finds nothing once the launch has reindexed Studio).
- **Droplets created from version 13 of the image** (Tutor 22.0.2) run Cubite's patched openedx image, built from `release/verawood.1`, which lacks the fixes for the Open edX security advisories of 2026-10-29. The same steps move them to Tutor 22.0.4 and its stock images in place: their `openedx-image-check` sees that Tutor now builds `release/verawood.2`, unsets `DOCKER_IMAGE_OPENEDX` and disables the cubitefixes plugin, and the launch pulls Tutor's images, runs the database migrations and `reindex_studio`, which fills Verawood.2's new `studio_library_content` search index. Without `openedx-image-check`, the Droplet would keep the patched image and miss those fixes. After the switch, nothing in Tutor's configuration points at `ghcr.io/amirtds/cubite-openedx` and the Droplet's secrets are unchanged. Three leftovers can go: the login message still shows version 13's setup summary (edit or delete `/var/lib/cubite-openedx/summary.txt`), `/opt/cubite/openedx-image.env` still pins the patched image, which a Droplet cloned from a snapshot of this one would pull again at first boot (delete the file), and the patched image stays on disk (`docker image rm` it).
- **The next named Open edX release** (Willow, Tutor 23) gets a new image. Existing Droplets follow Tutor's upgrade documentation: <https://docs.tutor.edly.io/upgrading.html>. On a Droplet that still runs Cubite's patched openedx image, run `openedx-image-check` after installing Tutor 23: it moves the Droplet to Tutor's own image, then asks for `tutor local upgrade --from=verawood` before `tutor local launch`, because it saves Tutor's environment and launch would otherwise skip the Verawood-to-Willow upgrade steps.
- **Droplets from the 2021 Lilac image** cannot be upgraded in place to this Tutor-based image. Start a new Droplet and move the courses, for example with Studio's export and import.

## Security

See [SECURITY.md](SECURITY.md) for how to report a problem and where security announcements are posted.

- The image is a starting point for a single-server Open edX platform. Whoever runs a Droplet is responsible for keeping it updated.
- Only ports 22, 80 and 443 are open. MySQL, MongoDB and Redis stay on Tutor's internal Docker network; Meilisearch is reached only through Caddy at `meilisearch.<LMS domain>`, where every request but `/health` needs one of its API keys. Caddy's 80 and 443 are published by Docker, whose own iptables rules apply before ufw.
- `config.yml`, `/root/.digitalocean_password`, `setup.log` and `firstboot.log` are readable by root only.
- **Tutor's stock images.** Droplets run Tutor's own openedx and MFE images (`overhangio/openedx:22.0.4-indigo` and `overhangio/openedx-mfe:22.1.2-indigo`), built from `release/verawood.2`. That release has the fixes for the five edx-platform advisories of 2026-10-29 and the three that version 13's patched image cherry-picked, and some of its fixes change behaviour. Every course asset is served with `Content-Security-Policy: sandbox`, so scripts in uploaded HTML or SVG files no longer run, JSInput problems included; the course waffle flag `course_assets.allow_unsafe_asset_rendering` turns that off for one course, and reopens the XSS for it. Studio's multi-video download is limited to 12 per user per hour (`VIDEO_DOWNLOAD_RATE_LIMIT`). And the forum's HTTP API is not routed unless `FORUM_ENABLE_HTTP_API` is set, which the platform itself does not need: it calls the forum in-process. XBlock handlers reached without signing in (`handler_noauth`) answer only when listed in the `XBLOCK_NOAUTH_HANDLER_ALLOWLIST` setting, so a third-party XBlock that relies on one needs its handler added there, and anonymous GETs on handler URLs are access-checked. Certificate Web/HTML View Overrides values are escaped when certificates render.
- **Patched openedx image (kept for a release that needs it).** When no Tutor release carries a needed fix, the image can ship a patched openedx image built by Cubite; none does since Tutor 22.0.4. [.github/workflows/openedx-image.yml](.github/workflows/openedx-image.yml) builds it on GitHub Actions with the same hash-pinned Tutor as the Droplets: Tutor's own `tutor images build openedx`, with the default plugins (mfe and indigo) plus forum, from the release tag plus the upstream commits that the Tutor plugin [files/opt/cubite/tutor-plugins/cubitefixes.yml](files/opt/cubite/tutor-plugins/cubitefixes.yml) cherry-picks through Tutor's `openedx-dockerfile-post-git-checkout` patch. The workflow checks the image for the fixes, pushes it to `ghcr.io/amirtds/cubite-openedx` with a tag of its own per run, so a published tag never moves, and prints the digest in the run summary. GitHub creates the package private: make it public once (package settings, Danger Zone, Change visibility) before running `packer build` with it pinned: Droplets pull it without credentials, and the installer checks that they can. That change cannot be undone. Never delete a package version that a snapshot pins. The file `files/opt/cubite/openedx-image.env` then holds one line, `OPENEDX_IMAGE=ghcr.io/amirtds/cubite-openedx@sha256:<digest>`, which first boot pulls and the wizard sets as `DOCKER_IMAGE_OPENEDX`; the wizard also enables the cubitefixes plugin, so that an openedx image built on the Droplet (extra XBlocks or a theme) keeps the fixes. The installer's gate requires that line, pinned by digest and pullable without credentials, for a release listed in `PATCHED_IMAGE_RELEASES`, and refuses it for any other; first boot and the wizard accept only the same pattern. Tutor cannot tag a build with a digest, so a build on such a Droplet first needs `tutor config save --set DOCKER_IMAGE_OPENEDX=<registry>/<name>:<tag>`; never unset `DOCKER_IMAGE_OPENEDX` to get past that while Tutor still builds the release without the fixes. `openedx-image-check` moves such a Droplet back to Tutor's own image once Tutor builds a release with the fixes. History: version 13 of the image (Tutor 22.0.2) pinned `ghcr.io/amirtds/cubite-openedx@sha256:05c71354306e4c78e244880137c273452edf9fa284c735faaa01dda211fe5510` (tag `22.0.2-indigo-cubite.2.1`, built and checked on 2026-10-20 by workflow run 2 from commit c1f90b4): `release/verawood.1` plus f657d158c2 (GHSA-g266-6v7f-j465), b5fc56a101 (GHSA-c6xg-fh3c-vvhh) and fc8dcdbcc9 (openedx-forum 0.4.2.post1, GHSA-c6fp-f54c-6cv4). Keep that package version public while Droplets from version 13 may still pull it.

## Support

- **Installer problems** (the image, the first-boot script, the wizard): open a GitHub issue on this repository. Issues are triaged once a week.
- **Questions about using the Open edX platform:** the Open edX forum, <https://discuss.openedx.org>.
- **Email:** hello@cubite.io.

Prefer not to run it yourself? Cubite offers managed Open edX hosting from $1,260 a month for up to 1,000 concurrent learners.
<https://cubite.io/open-edx?utm_source=github-1click>

Book a free 30-minute call with Cubite's founder: <https://cubite.io/go/book?src=github-1click>

## End-of-life rule

If a rebuild is more than 8 weeks late after a named Open edX release, the listing is relabelled as outdated or delisted, and this repository is archived with a pointer to its successor. The next named release is Willow, scheduled for December 2026 (<https://docs.openedx.org/en/latest/community/release_notes/index.html>), so its rebuild is due by February 2027.

## Repository layout

| Path | Purpose |
|---|---|
| `marketplace.pkr.hcl` | Packer template (HCL), converted from DigitalOcean's `marketplace-image.json` |
| `scripts/01-openedx-installer.sh` | Build-time installer |
| `scripts/02-ufw-openedx.sh` | Firewall rules |
| `scripts/90-cleanup.sh`, `scripts/99-img-check.sh` | DigitalOcean's cleanup and image check, unchanged from marketplace-partners commit b70878804ca27c01d5f5e882d26485defbaba210 |
| `files/var/lib/cloud/scripts/per-instance/001_onboot` | First boot: pulls the images |
| `files/opt/cubite/openedx-setup` | First-login setup wizard |
| `files/opt/cubite/openedx-image-check` | After a Tutor upgrade: keeps or drops the patched openedx image |
| `files/opt/cubite/openedx-image.env` | The pinned patched openedx image, only while a release needs one (absent since Tutor 22.0.4) |
| `files/opt/cubite/tutor-plugins/cubitefixes.yml` | Tutor plugin that cherry-picks the fixes, for the workflow and for Droplets with a patched image (not enabled since Tutor 22.0.4) |
| `.github/workflows/openedx-image.yml` | Builds, checks and publishes the patched openedx image (idle since Tutor 22.0.4) |
| `files/etc/update-motd.d/99-one-click` | Message of the day |
| `files/opt/cubite/requirements-*.in`, `requirements-*.txt` | pip-compile inputs and the hash-pinned lock files |
| `listing/` | Vendor Portal text drafts |

## License

The code in this repository is Copyright 2021-2026 Cubite Technologies Corp and licensed under the Apache License 2.0 ([LICENSE](LICENSE)). `scripts/90-cleanup.sh` and `scripts/99-img-check.sh` are DigitalOcean's (Apache-2.0) and keep their headers; `scripts/02-ufw-openedx.sh` is adapted from DigitalOcean's `02-ufw-nginx.sh`. Tutor and its plugins (AGPL-3.0) are licensed separately and installed from PyPI during the image build. The Open edX platform (AGPL-3.0) and the other services run from Docker images that each Droplet downloads at first boot, under their own licenses.

Open edX is a registered trademark of edX LLC. All Rights Reserved.
