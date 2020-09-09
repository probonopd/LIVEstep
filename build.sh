#!/bin/sh

# Exit on errors
set -e

version="12.1"
pkgset="branches/2020Q1"
desktop=$1
tag=$2
cwd="`realpath | sed 's|/scripts||g'`"
workdir="/usr/local"
livecd="${workdir}/furybsd"
cache="${livecd}/cache"
arch=AMD64
base="${cache}/${version}/base"
packages="${cache}/packages"
ports="${cache}/furybsd-ports-master"
iso="${livecd}/iso"
uzip="${livecd}/uzip"
cdroot="${livecd}/cdroot"
ramdisk_root="${cdroot}/data/ramdisk"
vol="furybsd"
label="FURYBSD"
isopath="${iso}/${vol}.iso"
export DISTRIBUTIONS="kernel.txz base.txz"
export BSDINSTALL_DISTSITE="http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/12.1-RELEASE/"
export BSDINSTALL_CHROOT="/usr/local/furybsd/uzip"
export BSDINSTALL_DISTDIR="/usr/local/furybsd/cache/12.1/base"

# Only run as superuser
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# Make sure git is installed
if [ ! -f "/usr/local/bin/git" ] ; then
  echo "Git is required"
  echo "Please install it with pkg install git or pkg install git-lite first"
  exit 1
fi

case $desktop in
  'kde')
    export desktop="kde"
    export edition="KDE"
    ;;
  'gnome')
    export desktop="gnome"
    export edition="GNOME"
    ;;
  'lumina')
    export desktop="lumina"
    export edition="LUMINA"
    ;;
  'mate')
    export desktop="mate"
    export edition="MATE"
    ;;
  *)
    export desktop="xfce"
    export edition="XFCE"
    ;;
esac

# Get the version tag
if [ -z "$2" ] ; then
  rm /usr/local/furybsd/tag >/dev/null 2>/dev/null || true
  export vol="FuryBSD-${version}-${edition}"
else
  rm /usr/local/furybsd/version >/dev/null 2>/dev/null || true
  echo "${2}" > /usr/local/furybsd/tag
  export vol="FuryBSD-${version}-${edition}-${tag}"
fi

label="FURYBSD"
isopath="${iso}/${vol}.iso"

workspace()
{
  umount ${uzip}/var/cache/pkg >/dev/null 2>/dev/null || true
  umount ${ports} >/dev/null 2>/dev/null || true
  rm -rf ${ports} >/dev/null 2>/dev/null || true
  umount ${cache}/furybsd-packages/ >/dev/null 2>/dev/null || true
  rm ${cache}/master.zip >/dev/null 2>/dev/null || true
  umount ${uzip}/dev >/dev/null 2>/dev/null || true
  zpool destroy furybsd >/dev/null 2>/dev/null || true
  mdconfig -d -u 0 >/dev/null 2>/dev/null || true
  if [ -f "${livecd}/pool.img" ] ; then
    rm ${livecd}/pool.img
  fi
  if [ -d "${livecd}" ] ;then
    # chflags -R noschg ${uzip} ${cdroot} >/dev/null 2>/dev/null || true
    rm -rf ${uzip} ${cdroot} ${ports} >/dev/null 2>/dev/null || true
  fi
  mkdir -p ${livecd} ${base} ${iso} ${packages} ${uzip} ${ramdisk_root}/dev ${ramdisk_root}/etc >/dev/null 2>/dev/null
  truncate -s 3g ${livecd}/pool.img
  mdconfig -f ${livecd}/pool.img -u 0
  gpart create -s GPT md0
  gpart add -t freebsd-zfs md0
  zpool create furybsd /dev/md0p1
  zfs set mountpoint=${uzip} furybsd
  zfs set compression=gzip-6 furybsd
}

base()
{
  export nonInteractive="YES"
  if [ ! -f "${base}/base.txz" ] ; then 
    bsdinstall distfetch
  fi
  
  if [ ! -f "${base}/kernel.txz" ] ; then
    cd ${base}
    bsdinstall distfetch
  fi
  bsdinstall distextract
  cp /etc/resolv.conf ${uzip}/etc/resolv.conf
  chroot ${uzip} env PAGER=cat freebsd-update fetch --not-running-from-cron
  chroot ${uzip} freebsd-update install
  rm ${uzip}/etc/resolv.conf
}

packages()
{
  cp /etc/resolv.conf ${uzip}/etc/resolv.conf
  mkdir ${uzip}/var/cache/pkg
  mount_nullfs ${packages} ${uzip}/var/cache/pkg
  mount -t devfs devfs ${uzip}/dev
  while read p; do
    pkg-static -c ${uzip} install -y /var/cache/pkg/"${p}"-0.txz
  done <"${cwd}"/settings/overlays.common
  cat "${cwd}/settings/packages.common" | xargs pkg-static -c "${uzip}" install -y
  cat ${cwd}/settings/packages.${desktop} | xargs pkg-static -c ${uzip} install -y
  if [ -f "${cwd}/settings/overlays.{$desktop}" ] ; then
    while read p; do
      pkg-static -c ${uzip} install -y /var/cache/pkg/"${p}"-0.txz
    done <"${cwd}/settings/overlays.{$desktop}"
  cat "${cwd}/settings/packages.${desktop}" | xargs pkg-static -c "${uzip}" install -y
  fi
  rm ${uzip}/etc/resolv.conf
  umount ${uzip}/var/cache/pkg
  umount ${uzip}/dev
}

rc()
{
  if [ ! -f "${uzip}/etc/rc.conf" ] ; then
    touch ${uzip}/etc/rc.conf
  fi
  if [ ! -f "${uzip}/etc/rc.conf.local" ] ; then
    touch ${uzip}/etc/rc.conf.local
  fi
  cat ${cwd}/settings/rc.conf.common | xargs chroot ${uzip} sysrc -f /etc/rc.conf.local
  cat ${cwd}/settings/rc.conf.${desktop} | xargs chroot ${uzip} sysrc -f /etc/rc.conf.local
}


repos()
{
  if [ ! -d "${cwd}/overlays/uzip/furybsd-common-settings" ] ; then
    git clone https://github.com/probonopd/furybsd-common-settings.git ${cwd}/overlays/uzip/furybsd-common-settings
  else
    cd ${cwd}/overlays/uzip/furybsd-common-settings && git pull
  fi

  # TODO: Move them to pkgs too, like common-settings
  if [ ! -d "${cache}/furybsd-wallpapers" ] ; then
    git clone https://github.com/furybsd/furybsd-wallpapers.git ${cache}/furybsd-wallpapers
  else
    cd ${cache}/furybsd-wallpapers && git pull
  fi
  if [ ! -d "${cache}/furybsd-xorg-tool" ] ; then
    git clone https://github.com/furybsd/furybsd-xorg-tool.git ${cache}/furybsd-xorg-tool
  else
    cd ${cache}/furybsd-xorg-tool && git pull
  fi
  if [ ! -d "${cache}/furybsd-wifi-tool" ] ; then
    git clone https://github.com/furybsd/furybsd-wifi-tool.git ${cache}/furybsd-wifi-tool
  else
    cd ${cache}/furybsd-wifi-tool && git pull
  fi
}

skel()
{
  mkdir -p ${uzip}/usr/share/skel/dot.config/xfce4/xfconf/xfce-perchannel-xml
  cp -R ${cache}/furybsd-xfce-settings/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/* ${uzip}/usr/share/skel/dot.config/xfce4/xfconf/xfce-perchannel-xml/
}

opt()
{
  mkdir -p ${uzip}/opt/local/bin
  mkdir -p ${uzip}/opt/local/share/backgrounds/furybsd
  cp ${cache}/furybsd-xorg-tool/bin/* ${uzip}/opt/local/bin/
  cp -R ${cache}/furybsd-wallpapers/*.png ${uzip}/opt/local/share/backgrounds/furybsd/
  cp ${cache}/furybsd-wifi-tool/bin/* ${uzip}/opt/local/bin/
}

user()
{
  mkdir -p ${uzip}/usr/home/liveuser/Desktop
  chroot ${uzip} echo furybsd | chroot ${uzip} pw mod user root -h 0
  chroot ${uzip} pw useradd liveuser -u 1000 \
  -c "Live User" -d "/home/liveuser" \
  -g wheel -G operator -m -s /bin/csh -k /usr/share/skel -w none
  chroot ${uzip} pw groupadd liveuser -g 1000
  chroot ${uzip} echo furybsd | chroot ${uzip} pw mod user liveuser -h 0
  chroot ${uzip} chown -R 1000:1000 /usr/home/liveuser
  chroot ${uzip} pw groupmod wheel -m liveuser
  chroot ${uzip} pw groupmod video -m liveuser
  chroot ${uzip} pw groupmod webcamd -m liveuser
}

dm()
{
  case $desktop in
    'kde')
      ;;
    'gnome')
      ;;
    'lumina')
      ;;
    'mate')
      chroot ${uzip} sed -i '' -e 's/memorylocked=128M/memorylocked=256M/' /etc/login.conf
      chroot ${uzip} cap_mkdb /etc/login.conf
      ;;
    'xfce')
      ;;
  esac
}

pkg()
{
  cd "${packages}"
  while read p; do
    echo "pkg #########################"
    sh -ex "${cwd}"/scripts/build-pkg.sh -m "${cwd}"/overlays/uzip/"${p}"/manifest -d "${cwd}"/overlays/uzip/"${p}/files"
  done <"${cwd}"/settings/overlays.common
  cd -
}

uzip() 
{
  install -o root -g wheel -m 755 -d "${cdroot}"
  # makefs "${cdroot}/data/system.ufs" "${uzip}"
  zpool export furybsd
  mkuzip -o "${cdroot}/data/system.uzip" "${livecd}/pool.img"
  zpool import furybsd
  zfs set mountpoint=/usr/local/furybsd/uzip furybsd
}

ramdisk() 
{
  cp -R ${cwd}/overlays/ramdisk/ ${ramdisk_root}
  cd "${uzip}" && tar -cf - rescue | tar -xf - -C "${ramdisk_root}"
  touch "${ramdisk_root}/etc/fstab"
  cp ${uzip}/etc/login.conf ${ramdisk_root}/etc/login.conf
  makefs -b '10%' "${cdroot}/data/ramdisk.ufs" "${ramdisk_root}"
  gzip "${cdroot}/data/ramdisk.ufs"
  rm -rf "${ramdisk_root}"
}

boot() 
{
  cp -R ${cwd}/overlays/boot/ ${cdroot}
  cd "${uzip}" && tar -cf - boot | tar -xf - -C "${cdroot}"
}

image() 
{
  sh ${cwd}/scripts/mkisoimages.sh -b $label $isopath ${cdroot}
  md5 $isopath > $isopath.md5

}

cleanup()
{
  if [ -d "${livecd}" ] ; then
    # chflags -R noschg ${uzip} ${cdroot} >/dev/null 2>/dev/null
    rm -rf ${uzip} ${cdroot} ${ports} >/dev/null 2>/dev/null
  fi
}

workspace
base
repos
pkg
packages
rc
opt
skel
user
dm
uzip
ramdisk
boot
image
cleanup
