#!/usr/bin/env bash
# =====================================================================
# Khoi dong RealSense D455 cho OpenVINS tren ROS2 Jazzy
# Thiet bi da xac nhan: Intel RealSense D455, serial 351322306551, FW 5.17.0.10
# =====================================================================
#
# !!! YEU CAU BAT BUOC: PHAI CAM VAO CONG USB 3.x !!!
#
# Kiem tra truoc khi chay:
#     rs-enumerate-devices -s
#     python3 -c "import pyrealsense2 as rs; \
#       print(list(rs.context().query_devices())[0].get_info(rs.camera_info.usb_type_descriptor))"
#
# Phai in ra "3.2". Neu in ra "2.1" thi DUNG LAI - o USB 2.1:
#     - Chi co MOT luong IR (infra1). infra2 KHONG ton tai -> khong stereo duoc.
#     - Khong co 848x480@30 (chi con 848x480@5 hoac @10).
# Doi sang cong USB-C toc do cao va dung dung cap USB3 kem theo may.

set -e

# --- Kiem tra bang thong truoc khi launch ---
USB=$(python3 -c "
import pyrealsense2 as rs
d=list(rs.context().query_devices())
print(d[0].get_info(rs.camera_info.usb_type_descriptor) if d else 'NO_DEVICE')
" 2>/dev/null || echo "UNKNOWN")

echo "USB type phat hien duoc: $USB"
if [ "$USB" = "NO_DEVICE" ]; then
  echo "LOI: khong thay camera nao. Kiem tra cap." >&2
  exit 1
fi
if [ "${USB%%.*}" = "2" ]; then
  echo "CANH BAO: dang o USB $USB -> khong du bang thong cho stereo 848x480@30." >&2
  echo "          Hay doi sang cong USB 3.x truoc khi chay OpenVINS." >&2
  exit 1
fi

ros2 launch realsense2_camera rs_launch.py \
  depth_module.emitter_enabled:=0 \
  enable_infra1:=true \
  enable_infra2:=true \
  enable_depth:=false \
  enable_color:=false \
  depth_module.infra_profile:=848x480x30 \
  enable_gyro:=true \
  enable_accel:=true \
  gyro_fps:=400 \
  accel_fps:=250 \
  unite_imu_method:=2 \
  global_time_enabled:=true \
  depth_module.enable_auto_exposure:=false \
  depth_module.exposure:=3000 \
  depth_module.gain:=64

# -----------------------------------------------------------------
# VE CHONG NHOE CHUYEN DONG (motion blur)
#
# Do tu metadata cua frame that (khong phai tham so mac dinh):
#       actual_exposure = 19946 us = ~20 ms  !!!
# Voi fx = 433 px, mot goc 1 do ung voi ~7.56 pixel, vet nhoe la:
#       blur_px = fx * omega(rad/s) * t_exposure
#   Tai 20ms:  115 do/s -> 17 px | 285 do/s -> 43 px | 570 do/s -> 87 px
#   Tai  3ms:  115 do/s ->  3 px | 285 do/s ->  6 px | 570 do/s -> 13 px
# min_px_dist = 15, nen o 20ms chi can lac vua phai la KLT da mat bam.
#
# LUU Y: cach dung auto_exposure_limit KHONG co tac dung tren D455 nay
# (da thu: dat limit=3000 nhung actual_exposure van 19946).
# Phai TAT auto-exposure va dat thu cong thi moi an.
# Danh doi: anh toi hon -> phai tang gain (64) -> nhieu hon mot chut.
# Nhieu anh de chiu hon NHIEU so voi nhoe: nhieu chi lam feature kem
# chinh xac, con nhoe lam MAT HAN feature.
#
# Neu phong toi qua, thu:
#   - Tang gain len 48-64
#   - Hoac noi long gioi han len 4000-5000us
#   - Hoac bat them den (anh IR nhay voi anh sang thuong va den halogen)
# -----------------------------------------------------------------

# Sau khi driver chay, o terminal khac:
#   python3 config/gen_realsense_calib.py -o config/rs_d455/kalibr_imucam_chain.yaml
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d455 \
#        max_cameras:=2 use_stereo:=true rviz_enable:=true
