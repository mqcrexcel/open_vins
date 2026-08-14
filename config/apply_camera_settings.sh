#!/usr/bin/env bash
# =====================================================================
# Ap dung cai dat camera SAU KHI driver da chay
#
# Cach dung:
#   Terminal 1:  bash config/rs_d455/launch_d455_ros2.sh
#   Terminal 2:  bash config/apply_camera_settings.sh        # mac dinh 3000us
#                bash config/apply_camera_settings.sh 1500   # cho drone
#
# TAI SAO DAT LUC CHAY THAY VI LUC LAUNCH
# ---------------------------------------
# Truyen depth_module.exposure qua dong lenh launch co dau hieu lam
# driver treo o buoc "Sync Mode: Off" (chua ket luan chac chan, nhung
# lan chay thanh cong dau tien khong he co cac tham so nay).
# Dat bang 'ros2 param set' sau khi sensor da mo thi DA KIEM CHUNG CHAY:
#     actual_exposure   : 19946 -> 3000
#     frame_laser_power :   150 -> 0
# =====================================================================

set -u
EXPOSURE="${1:-3000}"
GAIN="${2:-64}"
NODE="${NODE:-/camera/camera}"

echo "Ap dung cho $NODE: exposure=${EXPOSURE}us gain=${GAIN}"

# 1) TAT EMITTER - quan trong nhat.
#    Cac cham laser IR DUNG YEN so voi camera, nen khi camera di chuyen
#    chung khong dich trong anh. KLT se bam vao cham laser thay vi bam
#    vao canh vat -> he thong "thay" minh dung yen du dang di chuyen.
ros2 param set "$NODE" depth_module.emitter_enabled 0

# 2) CHONG NHOE CHUYEN DONG
#    Do thuc te: auto-exposure chay toi ~20ms trong nha.
#    blur_px = fx * omega(rad/s) * t_exposure   (fx ~ 433 -> 1 do ~ 7.56 px)
#      Tai 20ms: 115 do/s -> 17px | 285 do/s -> 43px | 570 do/s -> 87px
#      Tai  3ms: 115 do/s ->  3px | 285 do/s ->  6px | 570 do/s -> 13px
#    min_px_dist = 15 -> o 20ms chi can lac vua la KLT mat bam.
#
#    LUU Y: depth_module.auto_exposure_limit KHONG an (da thu: dat
#    limit=3000 nhung actual_exposure van 19946). Phai TAT auto-exposure.
ros2 param set "$NODE" depth_module.enable_auto_exposure false
ros2 param set "$NODE" depth_module.exposure "$EXPOSURE"
ros2 param set "$NODE" depth_module.gain "$GAIN"

sleep 2

# --- Xac minh bang METADATA, khong tin tham so ---
# depth_module.exposure chi la gia tri thu cong, KHONG phai gia tri that.
echo "--- Kiem chung tu metadata frame that ---"
timeout 15 ros2 topic echo --once --full-length /camera/camera/infra1/metadata 2>/dev/null \
  > /tmp/_rs_meta.txt || { echo "  Khong doc duoc metadata (driver co dang chay?)"; exit 1; }

python3 - <<'EOF'
import re, json, sys
try:
    s = open('/tmp/_rs_meta.txt').read()
    d = json.loads(re.search(r'json_data:\s*.(\{.*\}).', s, re.S).group(1))
except Exception as e:
    sys.exit("  Khong phan tich duoc metadata: %s" % e)

exp   = d.get('actual_exposure')
laser = d.get('frame_laser_power')
gain  = d.get('gain_level')
print("  actual_exposure   = %s us" % exp)
print("  gain_level        = %s" % gain)
print("  frame_laser_power = %s" % laser)

ok = True
if laser not in (0, None):
    print("  !! EMITTER VAN BAT -> KLT se bam vao cham laser, VIO se sai"); ok = False
if exp is not None and exp > 6000:
    print("  !! PHOI SANG VAN CAO (%s us) -> se nhoe khi di chuyen nhanh" % exp); ok = False
print("  => %s" % ("OK, san sang chay OpenVINS" if ok else "CHUA DAT, xem canh bao tren"))
EOF
