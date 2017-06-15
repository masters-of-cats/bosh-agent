#!/bin/bash

set -e -x

env

stemcell_tgz=/tmp/stemcell.tgz
stemcell_dir=/tmp/stemcell
image_dir=/tmp/image

mkdir -p $stemcell_dir $image_dir
wget -O- $STEMCELL_URL > $stemcell_tgz
echo "$STEMCELL_SHA1  $stemcell_tgz" | shasum -c -

# Expose loopbacks in concourse container
(
  set -e
  mount_path=/tmp/self-cgroups
  cgroups_path=`cat /proc/self/cgroup|grep devices|cut -d: -f3`
  [ -d $mount_path ] && umount $mount_path && rmdir $mount_path
  mkdir -p $mount_path
  mount -t cgroup -o devices none $mount_path
  echo 'b 7:* rwm' > $mount_path/$cgroups_path/devices.allow
  umount $mount_path
  rmdir $mount_path
  for i in $(seq 0 260); do
  	mknod -m660 /dev/loop${i} b 7 $i 2>/dev/null || true
  done
)

# Repack stemcell
(
	set -e;
	cd $stemcell_dir
	tar xvf $stemcell_tgz
	new_ver=`date +%s`

	# Update stemcell with new agent
	(
		set -e;
		cd $image_dir
		tar xvf $stemcell_dir/image
		mnt_dir=/mnt/stemcell
		mkdir $mnt_dir
		mount -o loop,offset=32256 root.img $mnt_dir
		echo -n 0.0.${new_ver} > $mnt_dir/var/vcap/bosh/etc/stemcell_version
		cp /tmp/build/*/agent-src/bin/bosh-agent $mnt_dir/var/vcap/bosh/bin/bosh-agent

		if [ -n "$BOSH_DEBUG_PUB_KEY" ]; then
			sudo chroot $mnt_dir /bin/bash <<EOF
			        groupadd bosh_sudoers
				groupadd bosh_sshers
				useradd -m -s /bin/bash bosh_debug -G bosh_sudoers,bosh_sshers
				cd ~/bosh_debug
				mkdir .ssh
				echo $BOSH_DEBUG_PUB_KEY >> .ssh/authorized_keys
				chmod go-rwx -R .
				chown -R bosh_debug:bosh_debug .
EOF

			 sudo chroot $mnt_dir /bin/bash <<EOF
			   mkdir -p /tmp/user/0
			   echo "nameserver 8.8.8.8" > /etc/resolv.conf
			   apt update
			   apt install git autoconf autopoint -y
			   cd /tmp
			   wget https://www.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v1.43.4/e2fsprogs-1.43.4.tar.gz
			   tar xzf e2fsprogs-1.43.4.tar.gz
			   cd e2fsprogs-1.43.4
			   ./configure
			   make
			   make install

			   cd ..
			   git clone git://git.kernel.org/pub/scm/utils/quota/quota-tools.git
			   cd quota-tools
			   ./autogen.sh && ./configure && make
			   make

			   extended_version=4.6.7-040607_4.6.7-040607.201608160432
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
			   popd

			   sed -i "s/$(uname -r)/${specific_version}/" /boot/grub/menu.lst
EOF
    fi

		umount $mnt_dir
		tar czvf $stemcell_dir/image *
	)

	sed -i.bak "s/version: .*/version: 0.0.${new_ver}/" stemcell.MF
	tar czvf $stemcell_tgz *
)

cp $stemcell_tgz /tmp/build/*/stemcell/
