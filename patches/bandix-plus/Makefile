include $(TOPDIR)/rules.mk

PKG_NAME:=bandix-plus
PKG_VERSION:=0.1.2
PKG_RELEASE:=2

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=timsaya

# LEDE: count-forwarded-only eBPF patch; binary built on host in diy-part2 (see scripts/build-bandix-plus-patched.sh).
# LEDE_BANDIX_COUNT_FORWARDED:=1

PKG_SOURCE:=v0.1.2.tar.gz
PKG_SOURCE_URL:=https://github.com/timsaya/bandix-plus/archive/refs/tags
PKG_HASH:=ae1179018a709b46455c551c46a2b6ffc458aad2f276999c82f13e2a569362f3

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=Bandix Plus - Network traffic monitoring tool (LEDE patched build)
	DEPENDS:=+zoneinfo-all +conntrack +iw
endef

define Package/$(PKG_NAME)/description
	Bandix Plus core service. LEDE build includes count-forwarded-only
	(eBPF counts traffic after rate-limit drops so UI matches throughput).
endef

define Build/Prepare
	tar -xzf "$(DL_DIR)/$(PKG_SOURCE)" -C "$(PKG_BUILD_DIR)" --strip-components=1
	$(Build/Patch)
endef

define Build/Compile
	[ -f "$(CURDIR)/lede-patched/bandix-plus" ] || { \
		echo "ERROR: missing $(CURDIR)/lede-patched/bandix-plus — run diy-part2 (build-bandix-plus-patched.sh)" >&2; \
		exit 1; \
	}
	# Do not use $(PKG_BUILD_DIR)/bandix-plus — source tree already has bandix-plus/ crate dir.
	$(CP) "$(CURDIR)/lede-patched/bandix-plus" "$(PKG_BUILD_DIR)/bandix-plus.bin"
	chmod 0755 "$(PKG_BUILD_DIR)/bandix-plus.bin"
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bandix-plus.bin $(1)/usr/bin/bandix-plus

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_BIN) ./files/bandix-plus.init $(1)/etc/init.d/bandix-plus

	$(INSTALL_DIR) $(1)/usr/share/bandix-plus
	$(INSTALL_CONF) ./files/bandix_plus.config $(1)/etc/config/bandix_plus

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/99-bandix-plus-defaults $(1)/etc/uci-defaults/99-bandix-plus-defaults

	$(INSTALL_DIR) $(1)/lib/upgrade/keep.d
	$(INSTALL_DATA) ./files/bandix-plus.keep $(1)/lib/upgrade/keep.d/bandix-plus
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/bandix_plus
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] && exit 0

DEFAULTS_SCRIPT="/etc/uci-defaults/99-bandix-plus-defaults"
if [ -x "$$DEFAULTS_SCRIPT" ]; then
	"$$DEFAULTS_SCRIPT" && rm -f "$$DEFAULTS_SCRIPT"
fi

exit 0
endef

$(eval $(call BuildPackage,bandix-plus))
