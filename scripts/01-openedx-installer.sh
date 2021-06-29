#!/bin/bash
sleep 20
sudo apt-get update -y
sudo apt-get upgrade -y
wget https://raw.githubusercontent.com/edx/configuration/open-release/lilac.master/util/install/ansible-bootstrap.sh -O - | sudo bash
mkdir edx-configs && cd edx-configs
sudo wget https://raw.githubusercontent.com/edx/configuration/open-release/lilac.master/playbooks/sample_vars/passwords.yml
sudo wget https://raw.githubusercontent.com/cubite-tech/do-edx-configs/main/vars.yml
while IFS= read line; do REPLACE=$(LC_ALL=C < /dev/urandom tr -dc 'A-Za-z0-9' | head -c35) && echo "$line" | sed "s/\!\!null/\'$REPLACE\'/"; done < ./passwords.yml | sudo tee ./my-passwords.yml
mkdir /edx-themes && sudo chmod -R 777 /edx-themes && cd /edx-themes
git clone https://github.com/Cubite-Technologies/theme -b lilac cubite-theme
cd /edx/app/edx_ansible/edx_ansible/playbooks/ && git checkout open-release/lilac.master
sudo /edx/app/edx_ansible/venvs/edx_ansible/bin/ansible-playbook -c local ./openedx_native.yml -i 'localhost,' -e@/root/edx-configs/my-passwords.yml -e@/root/edx-configs/vars.yml
