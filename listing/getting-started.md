These steps take you from a new Droplet to a running Open edX® platform with HTTPS.

## 1. Choose a Droplet size

Use a Droplet with 8 GB of memory and 4 vCPUs, the size Cubite tests. On 4 GB with 2 vCPUs, setup adds a 2 GB swap file and runs slower; that size is not tested. Setup stops on smaller Droplets, because the Open edX database migrations fail with less than 4 GB of memory.

## 2. Point a domain at the Droplet

The Open edX platform needs a domain name: nothing answers on the Droplet's IP address until setup has run. At your DNS provider, create these two records, using your own domain instead of learn.example.com:

| Type | Name | Value |
|---|---|---|
| A | learn.example.com | your_droplet_public_ipv4 |
| CNAME | *.learn.example.com | learn.example.com |

The wildcard record covers Studio (studio.learn.example.com), the learner apps (apps.learn.example.com) and search (meilisearch.learn.example.com). If your DNS provider can proxy traffic, set both records to DNS only, so that Let's Encrypt can reach the Droplet. Delete any AAAA (IPv6) record for these names, unless it points at the Droplet's own IPv6 address. While you do this, the Droplet's first boot downloads the Open edX images in the background.

## 3. Log in and follow the setup wizard

```
ssh root@your_droplet_public_ipv4
```

The setup wizard starts on its own. It:

- waits for the first boot to finish;
- asks for your LMS domain, your platform name and an admin email address;
- checks your DNS records, and shows the records to create if they are not ready yet;
- generates this Droplet's own passwords and keys;
- starts the Open edX platform with HTTPS certificates from Let's Encrypt;
- creates your admin account.

Setup takes up to an hour on an 8 GB Basic Droplet, most of it database setup (58 minutes in Cubite's test of this image on 2026-10-20); the wizard prints a progress line at least every two minutes. You can stop it at any time and continue later with: `openedx-setup`. If the connection drops while the platform is starting, the launch keeps running; log in again later and the wizard completes setup.

## 4. Open your platform

- LMS: https://learn.example.com
- Studio: https://studio.learn.example.com
- Admin user: `admin`. The password is in `/root/.digitalocean_password`.

## 5. Set up email

DigitalOcean blocks SMTP ports 25, 465 and 587, so the platform cannot send account activation, password reset or notification email until you use an external SMTP provider on another port:

```
tutor config save --set RUN_SMTP=false --set SMTP_HOST=smtp.example.com --set SMTP_PORT=2525 --set SMTP_USERNAME=... --set SMTP_PASSWORD=... --set SMTP_USE_TLS=true
tutor local launch -I
```

## 6. Everyday commands

Run Tutor as root:

- `tutor local status`: list the containers
- `tutor local logs -f lms`: follow the LMS log
- `tutor local restart`: restart the platform
- `tutor local stop`, then `tutor local start -d`: stop and start the platform

Tutor's configuration, including this Droplet's passwords and keys, is in `/root/.local/share/tutor/config.yml`. Keep a backup of it. The setup logs are in `/var/log/cubite-openedx/`.

## 7. Updates

Ubuntu security updates install automatically. Open edX and Tutor updates and security notices are posted on the image's GitHub page, https://github.com/amirtds/cubite-do-marketplace. To apply a Tutor 22.0.x release:

```
/opt/tutor/venv/bin/pip install --upgrade "tutor[full]>=22.0.0,<23.0.0"
openedx-image-check
tutor local launch -I
```

This image runs Cubite's patched openedx image: Tutor 22.0.2's image rebuilt with three upstream Open edX security fixes that the Verawood.1 release lacks (GHSA-c6xg-fh3c-vvhh, GHSA-c6fp-f54c-6cv4 and GHSA-g266-6v7f-j465). `openedx-image-check` keeps it until Tutor's own image carries the fixes, then moves the Droplet back to Tutor's image. One of the fixes serves course files with a sandbox policy, so scripts in uploaded HTML or SVG files, JSInput problems included, no longer run. The course waffle flag `course_assets.allow_unsafe_asset_rendering` turns that off for one course, and reopens the vulnerability for it.

## 8. Support

Cubite builds and supports this image. DigitalOcean does not build or support it. For installer problems, open an issue at https://github.com/amirtds/cubite-do-marketplace/issues (triaged weekly) or email hello@cubite.io. For questions about using the Open edX platform, see the Open edX forum: https://discuss.openedx.org

Prefer not to run it yourself? Cubite offers managed Open edX hosting from $1,260 a month for up to 1,000 concurrent learners, with named-release upgrades included in every tier, each upgrade rehearsed on a UAT environment before production. Founder Amir Tadrisi has worked on Open edX since 2013. [Book a free 30-minute call with Amir](https://cubite.io/go/book?src=do-1click) about managed hosting, a platform you already run, or custom work.

Need a custom feature or integration? Cubite's custom development and integration work for the Open edX platform is $125/hr.

Open edX is a registered trademark of edX LLC. All Rights Reserved.
