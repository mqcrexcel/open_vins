#!/usr/bin/env bash
# =====================================================================
# Khoi dong RealSense D455 cho OpenVINS tren ROS2 Jazzy
# Thiet bi da xac nhan: Intel RealSense D455, serial 351322306551
# =====================================================================
#
# BAN TOI GIAN - CO Y
# -------------------
# Chi truyen dung nhung tham so CAN de mo luong. Cac cai dat khac
# (emitter, phoi sang, gain) duoc dat SAU khi driver chay, bang:
#     bash config/apply_camera_settings.sh
#
# Ly do: truyen depth_module.* qua dong lenh launch co dau hieu lam
# driver treo o buoc "Sync Mode: Off" (khong mo duoc luong nao, khong
# co topic nao). Lan chay THANH CONG dau tien khong he co cac tham so
# do. Dat bang 'ros2 param set' sau khi sensor da mo thi DA KIEM CHUNG:
#     actual_exposure   : 19946 -> 3000
#     frame_laser_power :   150 -> 0
#
# YEU CAU: PHAI CAM VAO CONG USB 3.x
#   O USB 2.1 chi co MOT luong IR (infra2 khong ton tai) va khong co
#   848x480@30 -> khong chay stereo duoc.

set -e

# -----------------------------------------------------------------
# TAT CORE DUMP - QUAN TRONG
#
# realsense2_camera_node co ~26 thread. Neu nhan Ctrl+\ (SIGQUIT),
# kernel phai DUNG TAT CA thread truoc khi ghi core dump. Neu co MOT
# thread ket trong driver USB (trang thai D, uninterruptible) thi no
# khong dung duoc -> core dump cho vo han -> tien trinh vao trang thai
# D va KHONG THE kill duoc, ke ca bang SIGKILL. Chi con cach rut cap.
ulimit -c 0

# -----------------------------------------------------------------
# CANH BAO: neu script DUNG IM o dong "Dang kiem tra camera..." thi
# driver UVC dang deadlock (tien trinh truoc khong thoat sach).
# Dau hieu: ps se thay tien trinh o STAT=D, wchan=uvc_ctrl_*
# CACH THOAT: RUT CAP USB cua camera ra roi cam lai.
# Hoac reset cong (can root, doi 2-1 thanh cong that su dang dung):
#   echo '2-1' | sudo tee /sys/bus/usb/drivers/usb/unbind
#   echo '2-1' | sudo tee /sys/bus/usb/drivers/usb/bind
# -----------------------------------------------------------------
echo "Dang kiem tra camera... (neu treo o day -> rut cap USB va cam lai)"
USB=$(timeout 15 python3 -c "
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

# 'exec' thay tien trinh bash bang ros2 launch, nen Ctrl+C di THANG toi
# ros2 launch thay vi phai qua mot lop bash trung gian.
exec ros2 launch realsense2_camera rs_launch.py \
  enable_infra1:=true enable_infra2:=true \
  enable_depth:=false enable_color:=false \
  enable_gyro:=true enable_accel:=true unite_imu_method:=2

# =====================================================================
# SAU KHI DRIVER CHAY (terminal khac)
# =====================================================================
# 1) Ap dung emitter + phoi sang (BAT BUOC truoc khi chay OpenVINS):
#      bash config/apply_camera_settings.sh
#
# 2) Kiem tra luong:
#      ros2 topic list | grep infra    # PHAI co ca infra1 VA infra2
#      ros2 topic hz /camera/camera/infra1/image_rect_raw
#      ros2 topic hz /camera/camera/imu
#
# 3) Kiem tra DO PHAN GIAI co khop config khong (config dat 848x480):
#      ros2 topic echo --once --no-arr /camera/camera/infra1/image_rect_raw \
#        | grep -E "height|width"
#    Ban toi gian nay khong ep infra_profile, nen driver dung mac dinh.
#    Neu KHAC 848x480, sua 'resolution' trong kalibr_imucam_chain.yaml
#    hoac them lai depth_module.infra_profile:=848x480x30 o tren.
#
# =====================================================================
# CHAY OpenVINS
# =====================================================================
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d455 \
#        max_cameras:=2 use_stereo:=true rviz_enable:=true
#
# KHOI TAO: giu yen 2-3 giay roi DI CHUYEN DUT KHOAT (tinh tien 20-30cm).
# Static initializer doi mot cu "jerk"; xoay tai cho khong du.
