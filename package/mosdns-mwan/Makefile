include $(TOPDIR)/rules.mk

PKG_NAME:=mosdns-mwan
PKG_VERSION:=1.0
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/mosdns-mwan
  SECTION:=net
  CATEGORY:=Network
  TITLE:=MosDNS multi-WAN generator and source-IP hash
  DEPENDS:=+mosdns +mwan3 +ucode +ucode-mod-uci +ucode-mod-ubus +ucode-mod-fs
endef

define Package/mosdns-mwan/description
  Replaces stock MosDNS generate_config. Reads LuCI UCI and writes
  /var/etc/mosdns.json. Applies the same source-IP hash to mwan3 and DNS.
endef

define Build/Compile
endef

define Package/mosdns-mwan/install
	$(INSTALL_DIR) $(1)/usr/libexec $(1)/usr/sbin $(1)/usr/share/mosdns
	$(INSTALL_DIR) $(1)/etc/hotplug.d/iface
	$(INSTALL_BIN) ./files/usr/libexec/mosdns-gen $(1)/usr/libexec/mosdns-gen
	$(INSTALL_BIN) ./files/usr/libexec/mosdns-apply-luci $(1)/usr/libexec/mosdns-apply-luci
	$(INSTALL_BIN) ./files/usr/libexec/wan-src-hash $(1)/usr/libexec/wan-src-hash
	$(INSTALL_BIN) ./files/usr/share/mosdns/gen-config-custom $(1)/usr/share/mosdns/gen-config-custom
	$(INSTALL_BIN) ./files/usr/sbin/wan-src-hash $(1)/usr/sbin/wan-src-hash
	$(INSTALL_BIN) ./files/etc/hotplug.d/iface/28-mosdns-rebind $(1)/etc/hotplug.d/iface/28-mosdns-rebind
	$(INSTALL_BIN) ./files/etc/hotplug.d/iface/29-mwan3-policy-live $(1)/etc/hotplug.d/iface/29-mwan3-policy-live
endef

$(eval $(call BuildPackage,mosdns-mwan))
