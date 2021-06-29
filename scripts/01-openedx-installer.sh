#!/bin/bash
sleep 20
sudo apt-get update -y
sudo apt-get upgrade -y
wget https://raw.githubusercontent.com/edx/configuration/open-release/lilac.master/util/install/ansible-bootstrap.sh -O - | sudo bash
cd /edx/app/edx_ansible/
sudo wget https://raw.githubusercontent.com/edx/configuration/open-release/lilac.master/playbooks/sample_vars/passwords.yml
while IFS= read line; do REPLACE=$(LC_ALL=C < /dev/urandom tr -dc 'A-Za-z0-9' | head -c35) && echo "$line" | sed "s/\!\!null/\'$REPLACE\'/"; done < ./passwords.yml | sudo tee ./my-passwords.yml
cd /edx/app/edx_ansible/edx_ansible/playbooks/ && git checkout open-release/lilac.master
sed -ri 's/^(\s*)(ecommerce_create_demo_data\s*:\s*true\s*$)/\1ecommerce_create_demo_data: false/' ./openedx_native.yml
sed -ri 's/^(\s*)(credentials_create_demo_data\s*:\s*true\s*$)/\1credentials_create_demo_data: false/' ./openedx_native.yml
sed -ri 's/^(\s*)(DEMO_ROLE_ENABLED\s*:\s*true\s*$)/\1DEMO_ROLE_ENABLED: false/' ./openedx_native.yml
sed -ri 's/^(\s*)(SANDBOX_ENABLE_DISCOVERY\s*:\s*true\s*$)/\1SANDBOX_ENABLE_DISCOVERY: false/' ./openedx_native.yml
sed -ri 's/^(\s*)(SANDBOX_ENABLE_ECOMMERCE\s*:\s*true\s*$)/\1SANDBOX_ENABLE_ECOMMERCE: false/' ./openedx_native.yml
sed -ri "s/^(\s*)(SANDBOX_ENABLE_ANALYTICS_API\s*:\s*'master'\s*$)/\1SANDBOX_ENABLE_ANALYTICS_API: false/" ./openedx_native.yml
sed -ri "s/^(\s*)(EDX_PLATFORM_VERSION\s*:\s*('master')\s*$)/\1EDX_PLATFORM_VERSION: 'open-release\/lilac.master'/" ./openedx_native.yml
sudo /edx/app/edx_ansible/venvs/edx_ansible/bin/ansible-playbook -c local ./openedx_native.yml -i 'localhost,' -e@/edx/app/edx_ansible/my-passwords.yml
sed -ri "s/^(\s*)(DEFAULT_SITE_THEME\s*:\s*''\s*$)/\1DEFAULT_SITE_THEME: 'cubite-theme'/" /edx/etc/lms.yml
sed -ri "s/^(\s*)(ENABLE_COMPREHENSIVE_THEMING\s*:\s*false\s*$)/\1ENABLE_COMPREHENSIVE_THEMING: true/" /edx/etc/lms.yml
sudo /edx/app/edx_ansible/venvs/edx_ansible/bin/ansible-playbook -c local ./openedx_native.yml -i 'localhost,' -e@/edx/app/edx_ansible/my-passwords.yml -t edxapp_cfg --extra-vars "EDXAPP_COMPREHENSIVE_THEME_DIRS=['/edx/var/edxapp/theme'] EDXAPP_LMS_BASE=$(hostname -I | cut -f1 -d' ') EDXAPP_CMS_BASE=$(hostname -I | cut -f1 -d' '):18010"
cd /edx/var/edxapp/themes
git clone https://github.com/Cubite-Technologies/theme -b lilac cubite-theme
/edx/bin/edxapp-update-assets
/edx/bin/supervisorctl restart all