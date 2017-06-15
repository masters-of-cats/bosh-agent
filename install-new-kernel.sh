extended_version=$1
version=$(echo ${extended_version} | sed "s/-generic//")
specific_version=$(echo ${extended_version} | cut -d _ -f1)
short_version="v$(echo ${specific_version} | cut -d - -f1)"

mkdir -p /var/vcap/data/kernel-${version}

add-apt-repository -y ppa:ubuntu-toolchain-r/test
apt-get update
apt-get install -y gcc-6 g++-6
unlink /usr/bin/gcc
ln -s /usr/bin/gcc-6 /usr/bin/gcc

sed -i "s/error UTS_UBUNTU_RELEASE_ABI/warning UTS_UBUNTU_RELEASE_ABI/" /usr/src/ixgbevf-3.3.2/src/kcompat.h

pushd /var/vcap/data/kernel-${version}
  wget http://kernel.ubuntu.com/~kernel-ppa/mainline/${short_version}/linux-headers-${version}_all.deb
  wget http://kernel.ubuntu.com/~kernel-ppa/mainline/${short_version}/linux-headers-${extended_version}_amd64.deb
  wget http://kernel.ubuntu.com/~kernel-ppa/mainline/${short_version}/linux-image-${extended_version}_amd64.deb

  dpkg -i *.deb

  rm -rf *.deb
popd

sed -i "s/$(uname -r)/${specific_version}/" /boot/grub/menu.lst
