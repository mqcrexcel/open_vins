#!/usr/bin/env bash
# =====================================================================
# Khoi dong RealSense D457 cho OpenVINS tren ROS2 Jazzy
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
# co topic nao). Dat bang 'ros2 param set' sau khi sensor da mo thi
# DA KIEM CHUNG chay dung.
#
# D457 KHAC D455/D435i O CHO NAO
# ------------------------------
# D457 dung giao tiep GMSL2/FAKRA, KHONG phai USB. No can:
#   - Bo deserializer (thuong tren NVIDIA Jetson)
#   - Kernel module d4xx (kiem tra: lsmod | grep d4xx)
# May x86 thong thuong chi co uvcvideo se KHONG thay duoc D457.
# Ve quang hoc thi D457 dung chung module D450 voi D455 -> baseline
# ~95mm, khac han D435i (50mm).

set -e

# -----------------------------------------------------------------
# TAT CORE DUMP - QUAN TRONG
#
# realsense2_camera_node co ~26 thread. Neu nhan Ctrl+\ (SIGQUIT),
# kernel phai DUNG TAT CA thread truoc khi ghi core dump. Neu co MOT
# thread ket trong driver video (trang thai D, uninterruptible) thi no
# khong dung duoc -> core dump cho vo han -> tien trinh vao trang thai
# D va KHONG THE kill duoc, ke ca bang SIGKILL. Chi con cach rut cap.
ulimit -c 0

# -----------------------------------------------------------------
# CANH BAO: neu script DUNG IM o dong "Dang kiem tra camera..." thi
# driver dang deadlock (tien trinh truoc khong thoat sach).
# Dau hieu: ps se thay tien trinh o STAT=D, wchan=uvc_ctrl_*
# CACH THOAT: RUT CAP ra roi cam lai (hoac reset link GMSL).
# -----------------------------------------------------------------
echo "Dang kiem tra camera... (neu treo o day -> rut cap va cam lai)"
INFO=$(timeout 15 python3 -c "
import pyrealsense2 as rs
d=list(rs.context().query_devices())
if not d:
    print('NO_DEVICE')
else:
    print(d[0].get_info(rs.camera_info.name))
" 2>/dev/null || echo "UNKNOWN")

echo "Thiet bi phat hien duoc: $INFO"

if [ "$INFO" = "NO_DEVICE" ]; then
  echo "LOI: khong thay camera RealSense nao." >&2
  echo "  - D457 dung GMSL2, can bo deserializer + kernel module d4xx" >&2
  echo "  - Kiem tra: lsmod | grep d4xx   (chi co uvcvideo la KHONG du)" >&2
  echo "  - Kiem tra: rs-enumerate-devices -s" >&2
  exit 1
fi

# Chan nham model: baseline khac nhau se pha hong rang buoc stereo
case "$INFO" in
  *D457*) ;;
  *D455*) echo "CANH BAO: day la D455, khong phai D457 (cung baseline ~95mm nen van chay)." >&2
          echo "          Nen dung config:=rs_d455 cho dung hieu chuan." >&2 ;;
  *D435*) echo "LOI: day la D435i (baseline 50mm), KHONG dung duoc config rs_d457 (95mm)." >&2
          echo "     Hay dung: bash config/rs_d435i/launch_d435i_ros2.example.sh" >&2
          exit 1 ;;
  *)      echo "CANH BAO: model khong nhan dang duoc, kiem tra lai config." >&2 ;;
esac

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
#    Neu KHAC 848x480, sua 'resolution' trong kalibr_imucam_chain.yaml.
#
# =====================================================================
# SINH HIEU CHUAN THAT (driver PHAI dang TAT)
# =====================================================================
#   python3 config/gen_realsense_calib.py -o config/rs_d457/kalibr_imucam_chain.yaml
#   colcon build --packages-select ov_msckf
#
# =====================================================================
# CHAY OpenVINS
# =====================================================================
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d457 \
#        max_cameras:=2 use_stereo:=true rviz_enable:=true
#
# KHOI TAO: giu yen 2-3 giay roi DI CHUYEN DUT KHOAT (tinh tien 20-30cm).
