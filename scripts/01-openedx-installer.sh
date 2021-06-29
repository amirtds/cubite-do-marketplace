#!/bin/bash
sleep 20
sudo apt-get update -y
sudo apt-get upgrade -y
wget https://raw.githubusercontent.com/edx/configuration/open-release/lilac.master/util/install/ansible-bootstrap.sh -O - | sudo bash
mkdir ansible_secrets && cd ansible_secrets
sudo wget https://raw.githubusercontent.com/edx/configuration/open-release/lilac.master/playbooks/sample_vars/passwords.yml
while IFS= read line; do REPLACE=$(LC_ALL=C < /dev/urandom tr -dc 'A-Za-z0-9' | head -c35) && echo "$line" | sed "s/\!\!null/\'$REPLACE\'/"; done < ./passwords.yml | sudo tee ./my-passwords.yml
cd /edx/app/edx_ansible/edx_ansible/playbooks/ && git checkout open-release/lilac.master
sudo /edx/app/edx_ansible/venvs/edx_ansible/bin/ansible-playbook -c local ./openedx_native.yml -i 'localhost,' -e@/root/ansible_secrets/my-passwords.yml --extra-vars "COMMON_ENABLE_DATADOG=false COMMON_ENABLE_SPLUNKFORWARDER=false ecommerce_create_demo_data=false credentials_create_demo_data=false DEMO_ROLE_ENABLED=false SANDBOX_ENABLE_DISCOVERY=false SANDBOX_ENABLE_ECOMMERCE=false SANDBOX_ENABLE_ANALYTICS_API=false EDX_PLATFORM_VERSION='open-release\lilac.master'"
sudo /edx/app/edx_ansible/venvs/edx_ansible/bin/ansible-playbook -c local ./openedx_native.yml -i 'localhost,' -e@/root/ansible_secrets/my-passwords.yml -t edxapp_cfg --extra-vars "EDXAPP_COMPREHENSIVE_THEME_DIRS=['/edx/var/edxapp/theme'] DEFAULT_SITE_THEME=cubite-theme ENABLE_COMPREHENSIVE_THEMING=true  EDXAPP_LMS_BASE=$(hostname -I | cut -f1 -d' ') EDXAPP_CMS_BASE=$(hostname -I | cut -f1 -d' '):18010"
cd /edx/var/edxapp/themes
git clone https://github.com/Cubite-Technologies/theme -b lilac cubite-theme
/edx/bin/edxapp-update-assets
/edx/bin/supervisorctl restart all