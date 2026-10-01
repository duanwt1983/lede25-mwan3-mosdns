include $(TOPDIR)/rules.mk

PKG_NAME:=lede-center-frpc
PKG_VERSION:=0.61.1
PKG_RELEASE:=1

PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=timsaya

PKG_SOURCE_URL:=https://github.com/fatedier/frp/releases/download/v$(PKG_VERSION)
PKG_BUILD_DIR:=$(BUILD_DIR)/frp-$(PKG_VERSION)

include $(INCLUDE_DIR)/package.mk

ifeq ($(ARCH),x86_64)
	FRP_ARCH:=linux_amd64
	PKG_HASH:=b22e35691a8d0be287c0091a87debf00c84f0bd75e792ad56885520173964b11
else ifeq ($(ARCH),aarch64)
	FRP_ARCH:=linux_arm64
	PKG_HASH:=5fbdd18441ef034dd94a097cd94b50292a207ed5b6b8afda2ccdf95bba0283d7
else
	$(error lede-center-frpc: unsupported ARCH $(ARCH))
endif

PKG_SOURCE:=frp_$(PKG_VERSION)_$(FRP_ARCH).tar.gz

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	TITLE:=frpc client for LEDE regional center hub
	DEPENDS:=@(x86_64||aarch64)
endef

define Package/$(PKG_NAME)/description
	Installs frpc $(PKG_VERSION) (prebuilt) for outbound tunnels to the
	regional access center. Configure via 系统 → 管理权 → 区域接入中心.
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/frp_$(PKG_VERSION)_$(FRP_ARCH)/frpc $(1)/usr/bin/frpc
endef

$(eval $(call BuildPackage,$(PKG_NAME))
