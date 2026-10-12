#!/bin/bash

sed -i 's/^# CONFIG_IWLWIFI is not set/CONFIG_IWLWIFI=m/' .config
sed -i 's/^# CONFIG_IWLDVM is not set/CONFIG_IWLDVM=m/' .config
sed -i 's/^# CONFIG_IWLMVM is not set/CONFIG_IWLMVM=m/' .config
sed -i 's/^# CONFIG_ATH9K is not set/CONFIG_ATH9K=m/' .config
sed -i 's/^# CONFIG_ATH9K_PCI is not set/CONFIG_ATH9K_PCI=m/' .config
sed -i 's/^# CONFIG_ATH10K is not set/CONFIG_ATH10K=m/' .config
sed -i 's/^# CONFIG_ATH10K_PCI is not set/CONFIG_ATH10K_PCI=m/' .config
sed -i 's/^# CONFIG_ATH11K is not set/CONFIG_ATH11K=m/' .config
sed -i 's/^# CONFIG_ATH11K_PCI is not set/CONFIG_ATH11K_PCI=m/' .config
sed -i 's/^# CONFIG_RTW88 is not set/CONFIG_RTW88=m/' .config
sed -i 's/^# CONFIG_RTW88_PCI is not set/CONFIG_RTW88_PCI=m/' .config
sed -i 's/^# CONFIG_RTW88_USB is not set/CONFIG_RTW88_USB=m/' .config
sed -i 's/^# CONFIG_RTW89 is not set/CONFIG_RTW89=m/' .config
sed -i 's/^# CONFIG_RTW89_PCI is not set/CONFIG_RTW89_PCI=m/' .config
sed -i 's/^# CONFIG_RTL8XXXU is not set/CONFIG_RTL8XXXU=m/' .config
sed -i 's/^# CONFIG_MT76_CORE is not set/CONFIG_MT76_CORE=m/' .config
sed -i 's/^# CONFIG_MT76x0E is not set/CONFIG_MT76x0E=m/' .config
sed -i 's/^# CONFIG_MT76x0U is not set/CONFIG_MT76x0U=m/' .config
sed -i 's/^# CONFIG_MT76x2E is not set/CONFIG_MT76x2E=m/' .config
sed -i 's/^# CONFIG_MT76x2U is not set/CONFIG_MT76x2U=m/' .config
sed -i 's/^# CONFIG_MT7603E is not set/CONFIG_MT7603E=m/' .config
sed -i 's/^# CONFIG_MT7615E is not set/CONFIG_MT7615E=m/' .config
sed -i 's/^# CONFIG_MT7663U is not set/CONFIG_MT7663U=m/' .config
sed -i 's/^# CONFIG_MT7915E is not set/CONFIG_MT7915E=m/' .config
sed -i 's/^# CONFIG_MT7921E is not set/CONFIG_MT7921E=m/' .config
sed -i 's/^# CONFIG_MT7921U is not set/CONFIG_MT7921U=m/' .config
sed -i 's/^# CONFIG_MT7921S is not set/CONFIG_MT7921S=m/' .config
sed -i 's/^# CONFIG_BRCMFMAC is not set/CONFIG_BRCMFMAC=m/' .config
sed -i 's/^# CONFIG_BRCMSMAC is not set/CONFIG_BRCMSMAC=m/' .config
sed -i 's/^# CONFIG_B43 is not set/CONFIG_B43=m/' .config

make olddefconfig
make -j"$(nproc)" modules
make modules_install
depmod -a
