#!/usr/bin/env bash
# =====================================================================
# Khoi dong RealSense D435i cho OpenVINS tren ROS2 Jazzy
# Thiet bi da xac nhan: Intel RealSense D435I, serial 030522071743
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
# KHAC BIET QUAN TRONG SO VOI D455
# --------------------------------
# * RGB cua D435i la ROLLING SHUTTER -> TUYET DOI khong dung
#   /color/image_raw cho VIO. Hai imager IR (infra1/infra2) moi la
#   GLOBAL SHUTTER. (D455 co RGB global shutter nen dung color duoc,
#   D435i thi KHONG.)
# * Baseline D435i ~50mm, D455/D457 ~95mm -> extrinsics cam1 khac han,
#   khong copy config qua lai duoc.

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
# -----------------------------------------------------------------
echo "Dang kiem tra camera... (neu treo o day -> rut cap USB va cam lai)"
INFO=$(timeout 15 python3 -c "
import pyrealsense2 as rs
d=list(rs.context().query_devices())
if not d:
    print('NO_DEVICE')
else:
    print(d[0].get_info(rs.camera_info.name) + '|' +
          d[0].get_info(rs.camera_info.usb_type_descriptor))
" 2>/dev/null || echo "UNKNOWN|")

NAME="${INFO%%|*}"
USB="${INFO##*|}"
echo "Thiet bi: $NAME | USB type: $USB"

if [ "$NAME" = "NO_DEVICE" ]; then
  echo "LOI: khong thay camera nao. Kiem tra cap (D435i can USB 3.x)." >&2
  exit 1
fi
if [ "${USB%%.*}" = "2" ]; then
  echo "CANH BAO: dang o USB $USB -> chi co MOT luong IR, khong stereo duoc." >&2
  echo "          Hay doi sang cong USB 3.x." >&2
  exit 1
fi

# Chan nham model: baseline khac nhau se pha hong rang buoc stereo
case "$NAME" in
  *D435*) ;;
  *D455*|*D457*) echo "LOI: day la $NAME (baseline ~95mm), KHONG dung config rs_d435i (50mm)." >&2
                 echo "     Hay dung script tuong ung trong config/rs_d455 hoac config/rs_d457." >&2
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
# CHAY OpenVINS
# =====================================================================
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d435i \
#        max_cameras:=2 use_stereo:=true rviz_enable:=true
#
# Neu may yeu, chay mono:
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d435i \
#        max_cameras:=1 use_stereo:=false rviz_enable:=true
#
# KHOI TAO: giu yen 2-3 giay roi DI CHUYEN DUT KHOAT (tinh tien 20-30cm).
