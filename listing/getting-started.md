These steps take you from a new Droplet to a running Open edX® platform with HTTPS.

## 1. Choose a Droplet size

8 GB of memory with 4 vCPUs is recommended. 4 GB with 2 vCPUs is the minimum; on those Droplets setup adds a 2 GB swap file. Setup stops on smaller Droplets, because the Open edX database migrations fail with less than 4 GB of memory.

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

Setup takes up to an hour on an 8 GB Basic Droplet, most of it database setup (57 minutes in Cubite's test on 2026-10-20); the wizard prints a progress line at least every two minutes. You can stop it at any time and continue later with: `openedx-setup`. If the connection drops while the platform is starting, the launch keeps running; log in again later and the wizard completes setup.

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
tutor local launch -I
```

If the setup summary says that the Droplet runs Cubite's patched openedx image, run `tutor config save --unset DOCKER_IMAGE_OPENEDX` before `tutor local launch -I` once the new Tutor release includes its fixes.

## 8. Support

Cubite builds and supports this image. DigitalOcean does not build or support it. For installer problems, open an issue at https://github.com/amirtds/cubite-do-marketplace/issues (triaged weekly) or email hello@cubite.io. For questions about using the Open edX platform, see the Open edX forum: https://discuss.openedx.org

Prefer not to run it yourself? Cubite runs managed Open edX from $1,260 a month for up to 1,000 concurrent learners.
https://cubite.io/open-edx?utm_source=do-1click

Open edX is a registered trademark of edX LLC. All Rights Reserved.
