#!/usr/bin/env bash
# =====================================================================
# Vi du khoi dong RealSense D457/D455 cho OpenVINS tren ROS2 Jazzy
# =====================================================================
#
# CAC THAM SO QUAN TRONG (khong duoc bo qua):
#
#  depth_module.emitter_enabled:=0
#     -> TAT bo phat IR chu dong. Neu bat, cac cham IR se in len anh
#        infra1/infra2 va pha hong hoan toan KLT feature tracking.
#        Day la loi pho bien nhat khi chay VIO voi RealSense.
#
#  unite_imu_method:=2   (2 = linear_interpolation)
#     -> Accel (~250Hz) va gyro (~400Hz) ve theo 2 luong rieng.
#        OpenVINS can MOT topic /imu duy nhat co ca 2. Neu khong bat,
#        topic /camera/camera/imu se khong ton tai.
#
#  global_time_enabled:=true
#     -> Dong bo timestamp cua camera sang dong ho he thong.
#
# Dung anh INFRA (global shutter, mono) thay vi COLOR cho VIO.

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
  global_time_enabled:=true

# Sau do o terminal khac:
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d457 rviz_enable:=true
