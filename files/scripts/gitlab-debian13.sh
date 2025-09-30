#!/bin/bash
set -e

GITLAB_URL="http://git.metrika-online.ru"
KEY_URL="https://packages.gitlab.com/gitlab/gitlab-ce/gpgkey"
KEY_FILE="/usr/share/keyrings/gitlab-archive-keyring.gpg"
REPO="https://packages.gitlab.com/gitlab/gitlab-ce/debian"
DISTRIB="bookworm"
SOURCE_FILE="/etc/apt/sources.list.d/gitlab_gitlab-ce.list"

DISK_ID="scsi-0QEMU_QEMU_HARDDISK_drive-scsi1"
DISK_DEV="/dev/disk/by-id/${DISK_ID}"
PARTITION_DEV="${DISK_DEV}-part1"
VG_ID="vg_data"
LV_ID="lv_gitlab"
LVM_DEV="/dev/mapper/${VG_ID}-${LV_ID}"
GITLAB_DATA="/var/opt/gitlab/"

if [ -b "${DISK_DEV}" ] && ! [ -b "${PARTITION_DEV}" ]; then
    # Создаем GPT таблицу и раздел на всем диске
    echo 'label: gpt
    ,,' | sfdisk "${DISK_DEV}"
    sleep 5
    # Проверяем, что раздел создался
    if [ -b "${PARTITION_DEV}" ]; then
    # Создаем LVM на созданном разделе
    pvcreate "${PARTITION_DEV}"
    vgcreate $VG_ID "${PARTITION_DEV}"
    lvcreate -n $LV_ID -l 100%FREE $VG_ID
    mkfs.xfs $LVM_DEV -f
        if [ -b "${LVM_DEV}" ]; then
        mkdir -p "${GITLAB_DATA}"
        if blkid "${LVM_DEV}" | grep -q 'TYPE="xfs"'; then
            mount "${LVM_DEV}" "${GITLAB_DATA}"
            if ! grep -q "${LVM_DEV}" /etc/fstab; then
            echo "${LVM_DEV}  ${GITLAB_DATA}  xfs defaults  0   0" >> /etc/fstab
            fi
        fi
        fi
    fi
fi



curl -fsSL "${KEY_URL}" | gpg --yes --dearmor -o $KEY_FILE
echo "deb [signed-by=${KEY_FILE}] ${REPO} ${DISTRIB} main" | tee $SOURCE_FILE
apt update
EXTERNAL_URL="${GITLAB_URL}" apt install -y gitlab-ce

cat << EOF >> /etc/gitlab/gitlab.rb
gitlab_rails['gitlab_duo_features_enabled'] = false
nginx['proxy_protocol'] = true
gitlab_workhorse['proxy_protocol'] = true
gitlab_rails['backup_path'] = "/var/opt/gitlab/backups"
EOF
gitlab-ctl reconfigure
cat /etc/gitlab/initial_root_password | grep 'Password: '
