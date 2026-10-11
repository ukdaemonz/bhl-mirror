#!/bin/bash

JOBS="${JOBS:-$(nproc)}"
INITIAL_DIR="${INITIAL_DIR:-$(pwd)}"
BHL_VERSION="0.0.1"
PUBLIC_INDEX_ADDRESS="77.105.133.52"
# Default configuration
PERMIT_ROOT_LOGIN="${PERMIT_ROOT_LOGIN:-yes}"
PASSWORD_AUTHENTICATION="${PASSWORD_AUTHENTICATION:-yes}"
KBD_INTERACTIVE_AUTHENTICATION="${KBD_INTERACTIVE_AUTHENTICATION:-no}"

if [[ -v JOBS ]]; then
    if [ "$JOBS" -eq 0 ] 2>/dev/null; then
        echo "MAKEJOBS cannot be '0'"
        echo "Re-run script with example 'JOBS=2 ./openssh-10.5p1.sh'"
        exit 1
    fi
fi

mkdir -pv /sources/extra/
cd /sources/extra || exit 1

# Check if index available and/or network is up
if curl "http://${PUBLIC_INDEX_ADDRESS}/" &>/dev/null; then
    echo "Public index of BlackHat working"
else
    echo "Public index is not working or network is down"
    echo "Run 'sh ~/net-fix.sh' or manually set network up"
    exit 1
fi

rm -f openssh-10.5p1.tar.gz
wget "http://${PUBLIC_INDEX_ADDRESS}/blackhat-live/sources/${BHL_VERSION}/extra/openssh-10.5p1.tar.gz"

if [[ -f "openssh-10.5p1.tar.gz" ]]; then
    tar -xf openssh-10.5p1.tar.gz && cd openssh-10.5p1/ || exit 1
    install -v -g sys -m700 -d /var/lib/sshd
    groupadd -f -g 50 sshd
    id -u sshd &>/dev/null || useradd -c 'sshd PrivSep' \
        -d /var/lib/sshd          \
        -g sshd                   \
        -s /bin/false             \
        -u 50 sshd
    # If anything fails, do not clean sources, just exit with code 1
    if ! (
        ./configure --prefix=/usr                \
        --sysconfdir=/etc/ssh                    \
        --with-privsep-path=/var/lib/sshd        \
        --with-default-path=/usr/bin             \
        --with-superuser-path=/usr/sbin:/usr/bin \
        --with-pid-dir=/run
    ); then
        echo "Error: configure failed!"
        exit 1
    fi
    
    if ! (make -j"$JOBS" && make install); then
        echo "Error: installation failed!"
        exit 1
    fi
    
    sed -i -e '/^#*PermitRootLogin /d' \
           -e '/^#*PasswordAuthentication /d' \
           -e '/^#*KbdInteractiveAuthentication /d' /etc/ssh/sshd_config
    echo "PermitRootLogin ${PERMIT_ROOT_LOGIN}" >> /etc/ssh/sshd_config
    echo "PasswordAuthentication ${PASSWORD_AUTHENTICATION}" >> /etc/ssh/sshd_config
    echo "KbdInteractiveAuthentication ${KBD_INTERACTIVE_AUTHENTICATION}" >> /etc/ssh/sshd_config
    ssh-keygen -A
    cat > /etc/systemd/system/sshd.service << "EOF"
[Unit]
Description=OpenSSH Daemon
After=network.target

[Service]
ExecStartPre=/usr/sbin/sshd -t
ExecStart=/usr/sbin/sshd -D
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    # Checking for binaries
    if ! type -p scp sftp ssh ssh-add ssh-agent ssh-keygen ssh-keyscan sshd &>/dev/null; then
        echo "Error: binaries were not found in PATH!"
        exit 1
    fi
    /usr/sbin/sshd -t || exit 1
    # Enabling systemd unit
    systemctl enable sshd || exit 1
    
    cd "$INITIAL_DIR" || exit 1
else
    echo "No archive found."
    echo "Try to re-run this script"
    exit 1
fi
# Cleaning
rm -rf /sources/extra/openssh-10.5p1/
rm -f /sources/extra/openssh-10.5p1.tar.gz

echo "Successfully installed OpenSSH-10.5p1"
