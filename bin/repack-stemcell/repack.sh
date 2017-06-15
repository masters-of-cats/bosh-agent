#!/bin/bash

set -e -x

env

stemcell_tgz=/tmp/stemcell.tgz
stemcell_dir=/tmp/stemcell
image_dir=/tmp/image

agent_dir=${PWD}

mkdir -p $stemcell_dir $image_dir
wget -O- $STEMCELL_URL > $stemcell_tgz
echo "$STEMCELL_SHA1  $stemcell_tgz" | shasum -c -
rm -rf /tmp/build/hello
mkdir -p /tmp/build/hello

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
		mkdir -p $mnt_dir
		umount $mnt_dir || true
		mount -o loop,offset=32256 root.img $mnt_dir
		echo -n 0.0.${new_ver} > $mnt_dir/var/vcap/bosh/etc/stemcell_version
		cp ${agent_dir}/bin/bosh-agent $mnt_dir/var/vcap/bosh/bin/bosh-agent

		cd $mnt_dir/tmp
		# wget http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.8.17/linux-headers-4.8.17-040817_4.8.17-040817.201701090438_all.deb
		# wget http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.8.17/linux-headers-4.8.17-040817-generic_4.8.17-040817.201701090438_amd64.deb
		# wget http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.8.17/linux-image-4.8.17-040817-generic_4.8.17-040817.201701090438_amd64.deb


		cd $mnt_dir
		mount -t proc proc proc/
		chmod -R 777 tmp

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
EOF

		if [ -n "$BOSH_DEBUG_PUB_KEY" ]; then
			sudo chroot $mnt_dir /bin/bash <<EOF
				useradd -m -s /bin/bash bosh_debug -G bosh_sudoers,bosh_sshers
				cd ~bosh_debug
				mkdir .ssh
				echo $BOSH_DEBUG_PUB_KEY >> .ssh/authorized_keys
				chmod go-rwx -R .
				chown -R bosh_debug:bosh_debug .
EOF
    fi
    		umount $mnt_dir/proc
		cd $image_dir
		umount $mnt_dir
		tar czf $stemcell_dir/image *
	)

	sed -i.bak "s/version: .*/version: 0.0.${new_ver}/" stemcell.MF
	tar czvf $stemcell_tgz *
)

mkdir -p /tmp/build/hello/stemcell
cp $stemcell_tgz /tmp/build/hello/stemcell/
