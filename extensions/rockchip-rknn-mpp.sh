#
# SPDX-License-Identifier: GPL-2.0
#
# Rockchip media and NPU userspace for RK35xx vendor/legacy kernels:
# - MPP (video codecs) and RGA from the rockchip-multimedia PPA (Ubuntu jammy/noble)
# - RKNN runtime (librknnrt), headers and the Python rknn-toolkit-lite2 from airockchip/rknn-toolkit2
#
# The kernel must provide the MPP service and the RKNPU driver (rk35xx legacy/vendor do).

declare -g RKNN_VERSION="2.3.2"
declare -g RKNN_LIB_SHA256="d31fc19c85b85f6091b2bd0f6af9d962d5264a4e410bfb536402ec92bac738e8"
declare -g RKNN_WHEEL_CP312_SHA256="e1e4ec691fed900c0e6fde5e7d8eeba17f806aa45092b63b361ee775e2c1b50e"
declare -g ROCKCHIP_MULTIMEDIA_PPA_FPR="0B2F0747E3BD546820A639B68065BE1FC67AABDE"

function post_family_tweaks__rockchip_mpp_install() {
	if [[ "${RELEASE}" != "jammy" && "${RELEASE}" != "noble" ]]; then
		display_alert "${EXTENSION}" "rockchip-multimedia PPA has no ${RELEASE}; skipping MPP/RGA" "wrn"
		return 0
	fi

	display_alert "${EXTENSION}" "adding rockchip-multimedia PPA; installing MPP and RGA" "info"
	local keyring="/usr/share/keyrings/rockchip-multimedia.gpg"
	# Query via -G: run_host_command_logged re-parses with bash, so a literal "&" in the URL would background curl
	run_host_command_logged curl -fsSL -G -o "${SDCARD}/tmp/rockchip-multimedia.asc" \
		--data op=get --data "search=0x${ROCKCHIP_MULTIMEDIA_PPA_FPR}" https://keyserver.ubuntu.com/pks/lookup
	# Temporary GPG homedir: the builder's ~/.gnupg may be missing or not writable
	local gpg_tmp key_info
	gpg_tmp=$(mktemp -d)
	key_info=$(gpg --homedir "${gpg_tmp}" --batch --show-keys --with-colons "${SDCARD}/tmp/rockchip-multimedia.asc" 2>&1) || true
	if [[ "${key_info}" != *"fpr:::::::::${ROCKCHIP_MULTIMEDIA_PPA_FPR}:"* ]]; then
		rm -rf "${gpg_tmp}"
		exit_with_error "${EXTENSION}: rockchip-multimedia PPA key fingerprint mismatch" "${key_info}"
	fi
	run_host_command_logged gpg --homedir "${gpg_tmp}" --batch --yes --dearmor -o "${SDCARD}${keyring}" "${SDCARD}/tmp/rockchip-multimedia.asc"
	rm -rf "${gpg_tmp}" "${SDCARD}/tmp/rockchip-multimedia.asc"

	# HTTPS repository: CA certificates must be in place before apt reads it
	chroot_sdcard_apt_get_install ca-certificates
	echo "deb [signed-by=${keyring}] https://ppa.launchpadcontent.net/liujianfeng1994/rockchip-multimedia/ubuntu ${RELEASE} main" \
		> "${SDCARD}/etc/apt/sources.list.d/rockchip-multimedia.list"

	chroot_sdcard_apt_get_update
	chroot_sdcard_apt_get_install librockchip-mpp1 librockchip-mpp-dev rockchip-mpp-demos librga2 librga-dev

	# Device access for the video group. The PPA's rockchip-multimedia-config does this too,
	# but its postinst needs libv4l-0 and a running udev, so it fails in the build chroot.
	cat <<- 'RULES' > "${SDCARD}/etc/udev/rules.d/99-rockchip-mpp-rga.rules"
		KERNEL=="mpp_service", MODE="0660", GROUP="video"
		KERNEL=="rga", MODE="0660", GROUP="video"
		SUBSYSTEM=="dma_heap", MODE="0660", GROUP="video"
	RULES
}

function post_family_tweaks__rockchip_rknn_install() {
	display_alert "${EXTENSION}" "installing RKNN runtime ${RKNN_VERSION}" "info"
	local base="https://raw.githubusercontent.com/airockchip/rknn-toolkit2/v${RKNN_VERSION}"
	local api="${base}/rknpu2/runtime/Linux/librknn_api"

	run_host_command_logged curl -fsSL -o "${SDCARD}/usr/lib/librknnrt.so" "${api}/aarch64/librknnrt.so"
	echo "${RKNN_LIB_SHA256}  ${SDCARD}/usr/lib/librknnrt.so" | sha256sum -c --quiet ||
		exit_with_error "${EXTENSION}: librknnrt.so checksum mismatch"
	chroot_sdcard ldconfig

	local header
	for header in rknn_api.h rknn_custom_op.h rknn_matmul_api.h; do
		run_host_command_logged curl -fsSL -o "${SDCARD}/usr/include/${header}" "${api}/include/${header}"
	done

	# Python rknn-toolkit-lite2: one wheel per Python ABI; only noble (3.12) is pinned here
	if [[ "${RELEASE}" != "noble" ]]; then
		display_alert "${EXTENSION}" "no pinned rknn-toolkit-lite2 wheel for ${RELEASE}; skipping Python package" "wrn"
		return 0
	fi
	local wheel="rknn_toolkit_lite2-${RKNN_VERSION}-cp312-cp312-manylinux_2_17_aarch64.manylinux2014_aarch64.whl"
	run_host_command_logged curl -fsSL -o "${SDCARD}/tmp/${wheel}" "${base}/rknn-toolkit-lite2/packages/${wheel}"
	echo "${RKNN_WHEEL_CP312_SHA256}  ${SDCARD}/tmp/${wheel}" | sha256sum -c --quiet ||
		exit_with_error "${EXTENSION}: rknn-toolkit-lite2 wheel checksum mismatch"

	chroot_sdcard_apt_get_install python3-pip python3-numpy python3-psutil python3-ruamel.yaml
	chroot_sdcard pip3 install --no-deps --break-system-packages "/tmp/${wheel}"
	rm -f "${SDCARD}/tmp/${wheel}"
}
