#!/usr/bin/env bash
# =====================================================================
# Khoi dong RealSense D435i cho OpenVINS tren ROS2 Jazzy
# =====================================================================
#
# KHAC BIET QUAN TRONG SO VOI D455:
#
#  * D435i co camera RGB dung ROLLING SHUTTER.
#    -> TUYET DOI khong dung /color/image_raw cho VIO. Khi camera xoay
#       nhanh, moi hang pixel duoc chup o mot thoi diem khac nhau, lam
#       sai lech hinh hoc va pha vo mo hinh do cua bo loc.
#       (D455 co RGB global shutter nen dung color duoc - D435i thi KHONG.)
#    -> Luon dung infra1/infra2: hai imager IR nay la GLOBAL SHUTTER.
#
#  * Baseline D435i ~50mm (D455 ~95mm) -> extrinsics cam1 khac han,
#    khong copy duoc tu config D455.
#
# CAC THAM SO BAT BUOC:
#
#  depth_module.emitter_enabled:=0
#     -> TAT bo phat IR. Neu bat, cac cham laser IR se in len anh
#        infra1/infra2. Chung DUNG YEN so voi camera, nen KLT tracker
#        se bam vao cham laser thay vi bam vao canh vat -> VIO sai hoan
#        toan. Day la loi pho bien nhat khi chay VIO voi RealSense.
#
#  unite_imu_method:=2   (2 = linear_interpolation)
#     -> Gop accel va gyro thanh MOT topic /camera/camera/imu.
#        Khong bat thi topic nay khong ton tai.
#
#  global_time_enabled:=true
#     -> Dong bo timestamp camera voi dong ho he thong.

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
# CHONG NHOE CHUYEN DONG (motion blur)
#
# Do tren D455 cung ho: auto-exposure chay toi ~20ms (19946us) trong
# nha. Voi fx ~ 425 px (1 do ~ 7.4 pixel), vet nhoe la:
#       blur_px = fx * omega(rad/s) * t_exposure
#   Tai 20ms:  115 do/s -> 17 px | 285 do/s -> 42 px | 570 do/s -> 85 px
#   Tai  3ms:  115 do/s ->  3 px | 285 do/s ->  6 px | 570 do/s -> 13 px
# min_px_dist = 15 -> o 20ms chi can lac vua la KLT mat bam -> ODOM TROI.
#
# LUU Y: cach dung depth_module.auto_exposure_limit KHONG an (da thu
# tren D455: dat limit=3000 nhung actual_exposure van 19946us).
# Phai TAT han auto-exposure moi co tac dung.
#
# Kiem chung bang metadata (khong tin tham so, phai xem gia tri THUC):
#   ros2 topic echo --once --full-length /camera/camera/infra1/metadata \
#     | grep -o '"actual_exposure":[0-9]*'
# -----------------------------------------------------------------

# Kiem tra truoc khi chay OpenVINS:
#   ros2 topic hz /camera/camera/infra1/image_rect_raw   # ky vong ~30 Hz
#   ros2 topic hz /camera/camera/imu                     # ky vong ~400 Hz
#
# Chay OpenVINS (stereo):
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d435i \
#        max_cameras:=2 use_stereo:=true rviz_enable:=true
#
# Neu may yeu, chay mono cho nhe:
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d435i \
#        max_cameras:=1 use_stereo:=false rviz_enable:=true
