The Open edX® platform is open-source software for running online courses: an LMS for learners and Studio for course authors. This 1-Click image installs the current Open edX release, Verawood, with Tutor 22.0.2, the Docker-based Open edX distribution, on Ubuntu 24.04.

Setup is guided. The first time you log in as root, a setup wizard asks for your domain name, your platform name and an admin email address. It checks your DNS records, generates this Droplet's own passwords and keys, starts the Open edX platform with HTTPS certificates from Let's Encrypt, and creates your admin account. No passwords or keys are baked into the image, so every Droplet gets its own.

What the image includes:

- The Open edX Verawood release: the LMS, Studio and the micro-frontends, with the Indigo theme and discussion forums.
- Tutor 22.0.2 with its official plugins, installed with hash checking.
- Docker Engine 29 and Docker Compose 2, from Docker's own repository.
- A firewall that allows only SSH, HTTP and HTTPS, and automatic Ubuntu security updates.

What you need:

- A Droplet with 8 GB of memory and 4 vCPUs (recommended), or at least 4 GB and 2 vCPUs.
- A domain name, with an A record and a wildcard CNAME that point at the Droplet.
- An SMTP email provider, if the platform should send email: DigitalOcean blocks the standard SMTP ports.

Cubite builds and supports this image. DigitalOcean does not build or support it. For installer problems, open an issue on the image's GitHub repository (triaged weekly) or email hello@cubite.io. Questions about using the Open edX platform are welcome on the Open edX forum.

Open edX is a registered trademark of edX LLC. All Rights Reserved.
