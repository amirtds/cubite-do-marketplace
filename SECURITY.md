# Security policy

This policy covers Cubite's DigitalOcean 1-Click image for the Open edX® platform, built from this repository: the Packer template, the installer, the first-boot script, the setup wizard and the message of the day. Cubite builds and supports the image. DigitalOcean does not build or support it.

## Reporting a vulnerability

Please report security problems privately. Do not open a public GitHub issue for them.

- Email hello@cubite.io with "Security" in the subject, or
- use GitHub's private vulnerability reporting on this repository (Security tab, "Report a vulnerability"), where it is enabled.

Include what you found, the image version or snapshot date, and the steps to reproduce it. Cubite triages reports at least once a week and will tell you what it plans to do.

Problems in the software the image installs belong upstream:

- **The Open edX platform:** the Open edX Security Working Group, security@openedx.org.
- **Tutor and its plugins:** security.tutor@edly.io.
- **A specific Open edX site** built from this image: that site's operator.

## Where security announcements are posted

- **This image:** GitHub security advisories and release notes in this repository (Security and Releases tabs). A fix ships as a new image version on the DigitalOcean Marketplace and, when existing Droplets need action, as steps in the advisory.
- **The Open edX platform:** the security advisories of the openedx-platform repository, <https://github.com/openedx/openedx-platform/security/advisories>, and the Open edX forum, <https://discuss.openedx.org>.
- **Tutor:** its release notes, <https://github.com/overhangio/tutor/releases>.

## Supported versions

Only the latest image version on the DigitalOcean Marketplace is supported. Today that is Open edX Verawood with Tutor 22.0.2 on Ubuntu 24.04. Each named Open edX release gets a new image; if a rebuild is more than 8 weeks late, the listing is relabelled as outdated or delisted and this repository is archived.

## What the image does to stay safe

- No secrets, Tutor configuration or Docker images are baked into the snapshot. Each Droplet generates its own secrets the first time its owner runs the setup wizard.
- Tutor and its dependencies are installed with pip hash checking, and Docker comes from Docker's signed apt repository, held on the 29.x line that Docker still patches.
- The build fails if the openedx image would lack known critical fixes: with Tutor 22.0.0 to 22.0.2 it needs a patched image, and only test builds, whose snapshots are named `-UNPATCHED-TEST` and never submitted, can skip that.
- Only ports 22, 80 and 443 are open, and Ubuntu security updates install automatically.
- Logs that can contain passwords, the Tutor configuration and the admin password file are readable by root only.

Running a Droplet in production means keeping it updated: apply Open edX and Tutor security releases as they are announced, as described in the README.

Open edX is a registered trademark of edX LLC. All Rights Reserved.
