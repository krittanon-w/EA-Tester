#!/bin/sh -e

#
# Provisioning script
#

# Initialize script.
[ "$TRACE" ] && set -x
if [ ! -d /vagrant ] && [ ! -d /home/travis ] && [ ! -f /.dockerinit ]; then
  echo "Error: This script needs to be run within VM." >&2
  exit 1
elif [ -f ~/.provisioned ]; then
  echo "Note: System already provisioned, skipping." >&2
  exit 0
fi
echo "OS Type: $(uname -a)"
whoami && lsb_release -a && pwd
type curl || apt-get -y install curl
type dpkg apt-get

# Init variables.
id travis  && USER="travis"
id vagrant && USER="vagrant"

# Detect proxy.
GW=$(netstat -rn | grep "^0.0.0.0 " | cut -d " " -f10)
curl -s localhost:3128 --connect-timeout 2 > /dev/null && export http_proxy="http://localhost:3128"
curl -s       $GW:3128 --connect-timeout 2 > /dev/null && export http_proxy="http://$GW:3128"

case "$(uname -s)" in

  Linux)

    if type dpkg-reconfigure; then

        # Perform an unattended installation of a Debian packages.
        export DEBIAN_FRONTEND=noninteractive
        [ -f /etc/apt/apt.conf.d/70debconf ] && ex +"%s@DPkg@//DPkg" -scwq /etc/apt/apt.conf.d/70debconf
        dpkg-reconfigure debconf -f noninteractive
        echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections

        # Prepare wine dependencies.
        sudo find /etc/apt -type f -name '*.list' -execdir sed -i 's/^\(deb-src\)/#\1/' {} +  # Omit source repositories from updates

        # Add i386 architecture for Wine
        dpkg --add-architecture i386
    fi

    # Add PPA/Wine repository
    apt-get install -qy python-software-properties      # APT dependencies (required for the add-apt-repository command on Ubuntu).
    add-apt-repository -y ppa:wine/wine-builds          # Adds APT Wine repository.

    # Update APT repositories.
    set -x
    [ -n "$NO_APT_UPDATE" ] && apt-get -qq update
    set +x

    # Install necessary packages
    apt-get install -qy language-pack-en                                          # Language pack to prevent an invalid locale.
    apt-get install -qy python-software-properties                                # APT dependencies (required for a docker image).
    apt-get install -qy binutils coreutils moreutils cabextract zip unzip         # Common CLI utils.
    apt-get install -qy imagemagick                                               # ImageMagick.
    apt-get install -qy dbus                                                      # Required for Debian AMI on EC2.
    apt-get install -qy git realpath links html2text tree pv bc                   # Required commands.
    apt-get install -qy ca-certificates

    # Install wine and dependencies.
    apt-get install -qy --install-recommends wine-staging winehq-staging          # Wine from PPA/Wine and tools for MT4 installer.
    apt-get install -qy xvfb xdotool x11-utils xterm                              # Virtual frame buffer and X11 utils.
    #apt-get install -qy libgnutls-dev                                            # GNU TLS library for secure connections.

    # Setup swap file if none.
    if [ -z "$(swapon -s)" ]; then
      if [ -f /var/cache/swap/swapfile ]; then
        swapon /var/cache/swap/swapfile
      else
        mkdir -pv /var/cache/swap
        cd /var/cache/swap
        dd if=/dev/zero of=swapfile bs=1K count=4M
        chmod 600 swapfile
        mkswap swapfile
        swapon swapfile
        cd -
      fi
    fi
    ;;
  Darwin)
    brew install git
    brew install wine
  ;;
esac

# Set-up hostname.
grep "$(hostname)" /etc/hosts && echo "127.0.0.1 $(hostname)" >> /etc/hosts

# Set-up git.
git config --system user.name $USER
git config --system user.email "$USER@$HOSTNAME"
git config --system core.sharedRepository group

# Add version control for /opt.
git init /opt

# Give user write permission for /opt.
chown -R $USER /opt

# Mark system as provisioned.
> ~/.provisioned

echo "$0 done." >&2
