include $(TOPDIR)/rules.mk

PKG_NAME:=bandix-plus
PKG_VERSION:=0.1.2
PKG_RELEASE:=2

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=timsaya

# LEDE: build from upstream source + count-forwarded-only eBPF patch (not prebuilt release).
# LEDE_BANDIX_COUNT_FORWARDED:=1

PKG_SOURCE:=v0.1.2.tar.gz
PKG_SOURCE_URL:=https://github.com/timsaya/bandix-plus/archive/refs/tags
PKG_HASH:=ae1179018a709b46455c551c46a2b6ffc458aad2f276999c82f13e2a569362f3

PKG_BUILD_DEPENDS:=rust/host
PKG_BUILD_PARALLEL:=1

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-values.mk

ifeq ($(ARCH),x86_64)
	RUST_BANDIX_TARGET:=x86_64-unknown-linux-musl
else ifeq ($(ARCH),aarch64)
	RUST_BANDIX_TARGET:=aarch64-unknown-linux-musl
else ifeq ($(ARCH),arm)
	ARM_CPU_TYPE:=arm-armel
	ifeq ($(CONFIG_arm_v6)$(CONFIG_arm_v7),)
		ARM_CPU_TYPE:=$(subst arm-,armv5te-,$(ARM_CPU_TYPE))
	else ifeq ($(CONFIG_arm_v7),y)
		ARM_CPU_TYPE:=$(subst arm-,armv7-,$(ARM_CPU_TYPE))
	endif
	ifeq ($(CONFIG_HAS_FPU),y)
		ARM_CPU_TYPE:=$(subst -armel,-armhf,$(ARM_CPU_TYPE))
	endif
	ifeq ($(ARM_CPU_TYPE),arm-armel)
		RUST_BANDIX_TARGET:=arm-unknown-linux-musleabi
	else ifeq ($(ARM_CPU_TYPE),arm-armhf)
		RUST_BANDIX_TARGET:=arm-unknown-linux-musleabihf
	else ifeq ($(ARM_CPU_TYPE),armv5te-armel)
		RUST_BANDIX_TARGET:=armv5te-unknown-linux-musleabi
	else ifeq ($(ARM_CPU_TYPE),armv7-armel)
		RUST_BANDIX_TARGET:=armv7-unknown-linux-musleabi
	else ifeq ($(ARM_CPU_TYPE),armv7-armhf)
		RUST_BANDIX_TARGET:=armv7-unknown-linux-musleabihf
	else
		$(error bandix-plus: unsupported ARM CPU type $(ARM_CPU_TYPE))
	endif
else ifeq ($(ARCH),mips)
	RUST_BANDIX_TARGET:=mips-unknown-linux-musl
else ifeq ($(ARCH),mipsel)
	RUST_BANDIX_TARGET:=mipsel-unknown-linux-musl
else ifeq ($(ARCH),powerpc64)
	RUST_BANDIX_TARGET:=powerpc64le-unknown-linux-musl
else ifeq ($(ARCH),riscv64)
	RUST_BANDIX_TARGET:=riscv64gc-unknown-linux-musl
else
	$(error bandix-plus: LEDE patched source build not configured for ARCH $(ARCH))
endif

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
	$(SH) $(CURDIR)/lede-build-bandix.sh \
		$(PKG_BUILD_DIR) \
		$(PKG_BUILD_DIR)/bandix-plus \
		$(RUST_BANDIX_TARGET) \
		$(TARGET_CC_NOCACHE) \
		$(STAGING_DIR_HOST)
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bandix-plus $(1)/usr/bin/

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
