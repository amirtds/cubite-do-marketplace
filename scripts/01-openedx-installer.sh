!/bin/bash

# Sleep to wait for any system startup tasks
sleep 20

# Set front-end to be non-interactive
export DEBIAN_FRONTEND=noninteractive


# Update and upgrade the system packages without any prompts
sudo -E apt-get update -y
sudo -E apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-all"

# Install necessary dependencies
sudo apt-get install -y python3 python3-pip libyaml-dev

# Install Docker as per the Docker official installation guide
sudo apt-get remove docker docker-engine docker.io containerd runc # Ensures any old versions are removed
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/download/2.24.7/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Add the current user to the Docker group
sudo usermod -aG docker $USER

# Install Tutor as per the official documentation
sudo pip install "tutor[full]"

# Post-installation: re-login or use newgrp command to avoid logging out and back in
# newgrp docker

# Enable and start the Tutor web UI as a service
# Pre-fill the interactive questions with echo and pipe it to tutor local quickstart
echo -e 'y\nwww.myopenedx.com\nstudio.www.myopenedx.com\nMy Open edX\ncontact@www.myopenedx.com\nen\nN' | tutor local launch
sudo apt-get purge droplet-agent -y