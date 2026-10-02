# Rockchip RK3588 octa core 8GB RAM 64GB eMMC 2x GbE 5G WiFi6/BT SATA CAN RS485 LoRa IoT Gateway
BOARD_NAME="Dusun DSGW-380"
BOARD_VENDOR="dusun"
BOARDFAMILY="rockchip-rk3588"
BOARD_MAINTAINER=""
INTRODUCED="2024"
BOOTCONFIG="rk3588_defconfig" # Rockchip EVB U-Boot, same target as the vendor firmware (board is EVB7 V11 derived)
BOOT_SCENARIO="spl-blobs"
BOOT_SOC="rk3588"
KERNEL_TARGET="vendor,legacy" # Rockchip BSP: 6.1 (default) and 5.10 (as shipped by the vendor)
BOOT_FDT_FILE="rockchip/rk3588-dusun-dsgw-380.dtb"
IMAGE_PARTITION_TABLE="gpt"
DEFAULT_CONSOLE="both"
SERIALCON="ttyS2:1500000" # plain UART2; the device tree disables the FIQ debugger (no ttyFIQ0)
PACKAGE_LIST_BOARD="rfkill bluetooth bluez bluez-tools"
enable_extension "rockchip-rknn-mpp" # MPP, RGA and RKNN userspace

# Armbian's vendor U-Boot FIT (make_fit_atf.sh) packs only ATF + U-Boot, no OP-TEE,
# so drop the EVB defconfig's OP-TEE client to avoid SMC calls into a missing TEE.
function post_config_uboot_target__dsgw380_no_optee() {
	display_alert "u-boot for ${BOARD}" "disable OP-TEE client (no BL32 in FIT)" "info"
	# vendor 2017.09 tree has no scripts/config; olddefconfig runs afterwards
	local opt
	for opt in CONFIG_OPTEE_CLIENT CONFIG_OPTEE_V2 CONFIG_OPTEE_ALWAYS_USE_SECURITY_PARTITION; do
		sed -i "s/^${opt}=.*/# ${opt} is not set/" .config
	done
}

# WiFi: out-of-tree RTL8852BS SDIO driver. Bluetooth: RTL8852BS on UART6 via serdev hci_h5.
function custom_kernel_config__dsgw380_wireless() {
	opts_m+=("RTL8852BS")
	opts_y+=("SERIAL_DEV_BUS" "SERIAL_DEV_CTRL_TTYPORT" "BT_HCIUART_3WIRE" "BT_HCIUART_RTL")
}

# CAN debug output floods the kernel log with error-counter reads.
function custom_kernel_config__dsgw380_no_can_debug() {
	opts_n+=("CAN_DEBUG_DEVICES")
}
