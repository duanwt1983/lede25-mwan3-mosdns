#!/bin/bash
# Wireshark/tshark + tcpdump capture stack for OpenWrt/LEDE.
# Package names match menuconfig / CONFIG_PACKAGE_* symbols.

# Runtime packages baked into the firmware image.
WIRESHARK_RUNTIME_PKGS=(
  tcpdump
  libpcap
  wireshark
  libgcrypt
  libgpg-error
  glib2
  libffi
  libpcre2
  libxml2
  zlib
  libgnutls
  libnettle
  libgmp
  libtasn1
  libcares
  libcap
  libnl-core
  libnl-genl
  libnl-route
  libnghttp2
  libiconv-full
  libintl-full
)

# feeds/packages directory names (./scripts/feeds install -p packages …).
WIRESHARK_FEED_DIRS=(
  libpcap
  libgcrypt
  libgpg-error
  glib2
  libxml2
  gnutls
  libcap
  c-ares
  libnl
  libnghttp2
  libffi
  pcre2
  nettle
  gmp
  libtasn1
  gettext-full
  libiconv-full
)

# Map CONFIG_PACKAGE_* name → feeds/packages source directory.
wireshark_feed_dir() {
  case "$1" in
    libgnutls) echo gnutls ;;
    libpcre2) echo pcre2 ;;
    libcares) echo c-ares ;;
    libnettle) echo nettle ;;
    libgmp) echo gmp ;;
    libnghttp2) echo nghttp2 ;;
    libnl-core|libnl-genl|libnl-route) echo libnl ;;
    libintl-full) echo gettext-full ;;
    libiconv-full) echo libiconv-full ;;
    *) echo "$1" ;;
  esac
}

# Run from diy-part2.sh after overlay packages are copied (early fail if feeds missing).
wireshark_assert_deps() {
  local n dir mk seen="" d
  for n in "${WIRESHARK_RUNTIME_PKGS[@]}"; do
    dir=$(wireshark_feed_dir "$n")
    if echo "$seen" | grep -q " ${dir} "; then
      continue
    fi
    seen="${seen} ${dir} "
    mk=$(find package feeds \( -path "*/${n}/Makefile" -o -path "*/${dir}/Makefile" \) 2>/dev/null | head -n 1 || true)
    if [ -z "$mk" ]; then
      echo "ERROR: ${n} (feed dir ${dir}) has no Makefile; it will NOT be in the firmware"
      exit 1
    fi
    echo "wireshark dep ${n} <- ${mk}"
  done
}
