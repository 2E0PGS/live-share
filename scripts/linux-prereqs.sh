#!/usr/bin/env bash
#
# Copyright © Microsoft Corporation
# All rights reserved.
#
# Licensed under the MIT License. See LICENSE-CODE in the project root for details.
#
# Exit codes:
# 0 - Success
# 1 - Unexpected failure
# 3 - Do not have permissions to run command
# 4 - Distribution not supported by script
#

cat << EOF

Visual Studio Live Share Linux Dependency Installer

See https://aka.ms/vsls-docs/linux-prerequisites

Visual Studio Live Share requires a number of prerequisites that this script
will attempt to install for you. This process requires admin / root access.

EOF

# Script can skip installing .NET Core, keyring, or browser integretion dependencies.
# Pass false to the first argument to skip .NET Core, second to skip keyring, and 
# and third to skip browser integration dependency installation.
if [ "$1" = "false" ]; then NETCOREDEPS=0; else NETCOREDEPS=1; fi
if [ "$2" = "false" ]; then KEYRINGDEPS=0; else KEYRINGDEPS=1; fi
if [ "$3" = "false" ]; then BROWSERDEPS=0; else BROWSERDEPS=1; fi

# Utility function for exiting
exitScript()
{
    echo -e "\nPress enter to dismiss this message"
    read
    exit $1
}

# Wrapper function to only use sudo if not already root
sudoIf()
{
    if [ "$(id -u)" -ne 0 ]; then
        set -- command sudo "$@"
    fi
    "$@"
}

# Utility function that waits for any existing installation operations to complete
# on Debian/Ubuntu based distributions and then calls apt-get
aptSudoIf() 
{
    while sudoIf fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        echo -ne "(*) Waiting for other package operations to complete.\r"
        sleep 0.2
        echo -ne "(*) Waiting for other package operations to complete..\r"
        sleep 0.2
        echo -ne "(*) Waiting for other package operations to complete...\r"
        sleep 0.2
        echo -ne "\r\033[K"
    done
    sudoIf apt-get "$@"
}

# Installs .NET Core dependencies if not disabled
checkNetCoreDeps(){
    if [ $NETCOREDEPS -ne 0 ]; then
        echo -e "\n(*) Verifying .NET Core dependencies..."
        # Install .NET Core dependencies
        if ! "$@"; then
            echo "(!) .NET Core dependency install failed!"
            exitScript 1
        fi
    fi
}

# Installs keyring dependencies if not disabled
checkKeyringDeps(){
    if [ $KEYRINGDEPS -ne 0 ]; then
        echo -e "\n(*) Verifying keyring dependencies..."
        # Install keyring dependencies
        if ! "$@"; then
            echo "(!) Keyring installation failed!"
            exitScript 1
        fi
    fi 
}

# Installs browser integration dependencies if not disabled
checkBrowserDeps(){
    if [ $BROWSERDEPS -ne 0 ]; then
        echo -e "\n(*) Verifying browser integration dependencies..."
        # Install browser integration and clipboard dependencies
        if ! "$@"; then
            echo "(!) Browser dependency install failed!"
            exitScript 1
        fi
    fi
}


# If not already root, validate user has sudo access and error if not.
if [ "$(id -u)" -ne 0 ]; then

# Can't indent or text will be indented
cat << EOF
To begin the installation process, your OS will now ask you to enter your
admin / root (sudo) password.

EOF
    # Validate user actually can use sudo
    sudo -v > /dev/null 2>&1
    if [ $? -ne 0 ]; then

# Can't indent or text will be indented
cat << EOF
(!) Dependency installation failed! You do not have the needed admin / root
    access to install Live Share's dependencies. Contact your system admin
    and ask them to install the required libraries described here:
    https://aka.ms/vsls-docs/linux-required-lib-details
EOF
        exitScript 3
    else
        echo ""
    fi
fi

#openSUSE - Has to be first as apt is aliased to zypper
if type zypper > /dev/null 2>&1; then
    echo "(*) Detected SUSE (unoffically/community supported)"
    checkNetCoreDeps sudoIf zypper -n in libopenssl1_0_0 libicu krb5 libz1
    checkKeyringDeps sudoIf zypper -n in gnome-keyring libsecret-1-0
    checkBrowserDeps sudoIf zypper -n in desktop-file-utils xprop

# Debian / Ubuntu
elif type apt-get > /dev/null 2>&1; then
    echo "(*) Detected Debian / Ubuntu"
   
    # Get latest package data
    echo -e "\n(*) Updating package lists..."
    if ! aptSudoIf update; then
        echo "(!) Failed to update list of available packages!"
        exitScript 1
    fi

    if [ $NETCOREDEPS -ne 0 ]; then
        checkNetCoreDeps aptSudoIf install -yq libicu[0-9][0-9] libkrb5-3 zlib1g
        # Determine which version of libssl to install
        if ! LIBSSL=$(dpkg-query -f '${db:Status-Abbrev}\t${binary:Package}\n' -W 'libssl1\.0\.?' 2>&1); then
           echo "(!) Failed see if libssl already installed!"
           exitScript 1
        fi
        if [ "$(echo "$LIBSSL" | grep -o 'libssl1\.0\.[0-9]:' | uniq | sort | wc -l)" -eq 0 ]; then
            # No libssl install 1.0.2 for Debian, 1.0.0 for Ubuntu
            if [[ ! -z $(apt-cache --names-only search ^libssl1.0.2$) ]]; then
                if ! aptSudoIf install -yq libssl1.0.2; then
                    echo "(!) libssl1.0.2 installation failed!"
                    exitScript 1
                fi
            else    
                if ! aptSudoIf install -yq libssl1.0.0; then
                    echo "(!) libssl1.0.0 installation failed!"
                    exitScript 1
                fi
            fi
        else 
            echo "(*) libssl1.0.x already installed."
        fi
    fi

    checkKeyringDeps aptSudoIf install -yq gnome-keyring libsecret-1-0
    checkBrowserDeps aptSudoIf install -yq desktop-file-utils x11-utils

#RHL/Fedora/CentOS
elif type yum  > /dev/null 2>&1; then
    echo "(*) Detected RHL / Fedora / CentOS"

    # Update package repo indexes - don't exit on non-zero since if there's no upgrade a non-zero return occurs
    echo -e "\n(*) Updating package lists..."
    sudoIf yum check-update

    checkNetCoreDeps sudoIf yum -y install openssl-libs krb5-libs libicu zlib
    checkKeyringDeps sudoIf yum -y install gnome-keyring libsecret
    checkBrowserDeps sudoIf yum -y install desktop-file-utils xorg-x11-utils

#ArchLinux
elif type pacman > /dev/null 2>&1; then
    echo -e "(*) Detected Arch Linux (unoffically/community supported)"
    checkNetCoreDeps sudoIf pacman -Sq --noconfirm --needed gcr liburcu openssl-1.0 krb5 icu zlib
    checkKeyringDeps sudoIf pacman -Sq --noconfirm --needed gnome-keyring libsecret
    checkBrowserDeps sudoIf pacman -Sq --noconfirm --needed desktop-file-utils xorg-xprop

#Solus
elif type eopkg > /dev/null 2>&1; then
    echo "(*) Detected Solus (unoffically/community supported)"
    checkNetCoreDeps sudoIf eopkg -y it libicu openssl zlib kerberos
    checkKeyringDeps sudoIf eopkg -y it gnome-keyring libsecret
    checkBrowserDeps sudoIf eopkg -y it desktop-file-utils xprop

#Alpine Linux
elif type apk > /dev/null 2>&1; then
    echo "(*) Detected Alpine Linux"
    
    # Update package repo indexes    
    echo -e "\n(*) Updating and upgrading..."
    if ! sudoIf apk update --wait 30; then
        echo "(!) Failed to update package lists."
        exitScript 1
    fi
    # Upgrade to avoid package dependency conflicts
    if ! sudoIf apk upgrade; then
        echo "(!) Failed to upgrade."
        exitScript 1
    fi

    checkNetCoreDeps sudoIf apk add --no-cache libssl1.0 icu krb5 zlib
    checkKeyringDeps sudoIf apk add --no-cache gnome-keyring libsecret
    checkBrowserDeps sudoIf apk add --no-cache desktop-file-utils xprop

#If no supported package manager is found
else

# Can't indent or text will be indented
cat << EOF
(!) We are unable to automatically install dependencies for this version of"
    Linux. See https://aka.ms/vsls-docs/linux-prerequisites for information"
    on required libraries."

Press enter to dismiss this message.
EOF

    exitScript 4
fi

cat << EOF

(*) Success!

EOF
# Don't pause on exit here - we'll handle this in the extension
