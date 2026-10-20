#!/bin/sh
#
# 02-ufw-openedx.sh: firewall for Cubite's DigitalOcean 1-Click image for the
# Open edX platform. Allows SSH (22, rate-limited), HTTP (80) and HTTPS (443,
# TCP and UDP for HTTP/3) and nothing else.
#
# Adapted from scripts/02-ufw-nginx.sh in github.com/digitalocean/marketplace-partners
# (Copyright 2021 DigitalOcean LLC, licensed under the Apache License 2.0).
#
# Note: ports that Docker publishes (Caddy's 80 and 443) are filtered by
# Docker's own iptables rules before ufw sees them. Tutor publishes no other
# ports.

set -eu

ufw default deny incoming
ufw default allow outgoing
ufw limit 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp

ufw --force enable
ufw status verbose
