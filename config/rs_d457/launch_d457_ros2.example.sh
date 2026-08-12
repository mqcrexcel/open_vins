#!/usr/bin/env bash
# =====================================================================
# Example bring-up of a RealSense D457/D455 for OpenVINS on ROS 2 Jazzy
# =====================================================================
#
# IMPORTANT PARAMETERS (do not skip these):
#
#  depth_module.emitter_enabled:=0
#     -> Turn OFF the active IR projector. If left on, the IR dots are
#        printed onto the infra1/infra2 images and completely break KLT
#        feature tracking. This is the most common mistake when running
#        VIO with a RealSense.
#
#  unite_imu_method:=2   (2 = linear_interpolation)
#     -> Accel (~250Hz) and gyro (~400Hz) arrive as two separate streams.
#        OpenVINS needs a SINGLE /imu topic carrying both. Without this,
#        the /camera/camera/imu topic does not exist.
#
#  global_time_enabled:=true
#     -> Sync the camera timestamps to the system clock.
#
# Use the INFRA images (global shutter, mono) rather than COLOR for VIO.

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

# Then, in another terminal:
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d457 rviz_enable:=true
