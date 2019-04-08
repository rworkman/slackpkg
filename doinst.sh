config() {
  NEW="$1"
  OLD="$(dirname $NEW)/$(basename $NEW .new)"
  # If there's no config file by that name, mv it over:
  if [ ! -r $OLD ]; then
    mv $NEW $OLD
  elif [ "$(cat $OLD | md5sum)" = "$(cat $NEW | md5sum)" ]; then # toss the redundant copy
    rm $NEW
  fi
  # Otherwise, we leave the .new copy for the admin to consider...
}

copy_mirror_file() {
  ARCH=$(uname -m)
  case $ARCH in
    i386|i486|i586|i686)
      SRCMIRROR=mirrors-x86.sample
    ;;
    x86-64|x86_64|X86-64|X86_64)
      SRCMIRROR=mirrors-x86_64.sample
    ;;
    s390)
      SRCMIRROR=mirrors-s390.sample
    ;;
    arm*)
      SRCMIRROR=mirrors-arm.sample
    ;;
    *)
      SRCMIRROR=mirrors-x86.sample
    ;;
  esac
  cp usr/doc/slackpkg-@VERSION@/$SRCMIRROR etc/slackpkg/mirrors.new
}

copy_mirror_file
config etc/slackpkg/mirrors.new
config etc/slackpkg/slackpkg.conf.new
config etc/slackpkg/blacklist.new
rm -f var/lib/slackpkg/pkglist
rm -f var/lib/slackpkg/CHECKSUMS.md5*
