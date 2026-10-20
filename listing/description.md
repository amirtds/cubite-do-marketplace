Cubite's free 1-Click image installs the Open edX® platform, open-source software for running online courses (an LMS for learners and Studio for course authors), on your own domain with HTTPS. It sets up Verawood, the current Open edX release as of October 2026, with Tutor 22.0.2 on Ubuntu 24.04. Each named Open edX release gets a new image.

**Guided setup.** The first time you log in as root, a setup wizard asks for your domain, platform name and admin email, checks your DNS records, starts the platform with HTTPS certificates from Let's Encrypt and creates your admin account. Setup takes about an hour on an 8 GB Basic Droplet.

- **Your own secrets, no telemetry:** no passwords, keys or default admin account are baked into the image, and each Droplet generates its own. Nothing in the image reports back to Cubite.
- **Security fixes:** the platform runs Tutor's LMS and Studio image, rebuilt by Cubite with three upstream Open edX security fixes, two of them rated critical.
- **Firewall and updates:** a firewall allows only SSH, HTTP and HTTPS, and Ubuntu security updates install automatically.

**What you need**

- A Droplet with 8 GB of memory and 4 vCPUs.
- A domain with an A record and a wildcard CNAME that point at the Droplet.
- An external SMTP provider for email, because DigitalOcean blocks the standard SMTP ports.

**Prefer not to run it yourself?** With this image, you apply Open edX and Tutor updates, including each named-release upgrade. Cubite (cubite.io) offers managed Open edX hosting from $1,260/mo for up to 1,000 concurrent learners: a dedicated instance that Cubite builds, hosts and operates. Every managed tier includes daily backups and a quarterly restore rehearsal, SSO (SAML / OIDC) implementation, and named-release upgrades, each upgrade rehearsed on a UAT environment before production.

Founder Amir Tadrisi has worked on Open edX since 2013. **[Book a free 30-minute call with Amir](https://cubite.io/go/book?src=do-1click)** about managed hosting, a platform you already run, or custom work.

**Need a custom feature or integration?** Cubite's custom development and integration work for the Open edX platform is $125/hr.

**Support.** Cubite builds and supports this image. DigitalOcean does not build or support it. The code that builds it is public on GitHub under the Apache License 2.0. For installer problems, open an issue in that repository (triaged weekly) or email hello@cubite.io. For questions about using the Open edX platform, see the Open edX forum.

Open edX is a registered trademark of edX LLC. All Rights Reserved.
