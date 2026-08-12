#!/usr/bin/env bash
# =====================================================================
# Bring up a RealSense D435i for OpenVINS on ROS 2 Jazzy
# =====================================================================
#
# KEY DIFFERENCES FROM THE D455:
#
#  * The D435i RGB camera uses a ROLLING SHUTTER.
#    -> NEVER use /color/image_raw for VIO. When the camera rotates
#       quickly, each pixel row is captured at a different instant, which
#       distorts the geometry and breaks the filter's measurement model.
#       (The D455 has a global-shutter RGB so color is usable there - the
#       D435i is NOT.)
#    -> Always use infra1/infra2: both IR imagers are GLOBAL SHUTTER.
#
#  * D435i baseline ~50mm (D455 ~95mm) -> the cam1 extrinsics differ
#    entirely and cannot be copied from the D455 config.
#
# MANDATORY PARAMETERS:
#
#  depth_module.emitter_enabled:=0
#     -> Turn OFF the IR projector. If left on, the IR laser dots are
#        printed onto the infra1/infra2 images. They are STATIONARY
#        relative to the camera, so the KLT tracker locks onto the dots
#        instead of the scene -> VIO goes completely wrong. This is the
#        single most common mistake when running VIO with a RealSense.
#
#  unite_imu_method:=2   (2 = linear_interpolation)
#     -> Merge accel and gyro into ONE /camera/camera/imu topic.
#        Without it that topic does not exist.
#
#  global_time_enabled:=true
#     -> Sync the camera timestamps to the system clock.

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
# MOTION BLUR
#
# Measured on a D455 of the same family: auto-exposure runs up to ~20ms
# (19946us) indoors. With fx ~ 425 px (1 deg ~ 7.4 pixels), the blur is:
#       blur_px = fx * omega(rad/s) * t_exposure
#   At 20ms:  115 deg/s -> 17 px | 285 deg/s -> 42 px | 570 deg/s -> 85 px
#   At  3ms:  115 deg/s ->  3 px | 285 deg/s ->  6 px | 570 deg/s -> 13 px
# min_px_dist = 15 -> at 20ms even moderate shaking loses KLT track -> ODOM DRIFTS.
#
# NOTE: the depth_module.auto_exposure_limit approach does NOT work
# (tested on a D455: set limit=3000 but actual_exposure stayed 19946us).
# Auto-exposure must be fully DISABLED to have any effect.
#
# Verify via metadata (do not trust the parameter, read the ACTUAL value):
#   ros2 topic echo --once --full-length /camera/camera/infra1/metadata \
#     | grep -o '"actual_exposure":[0-9]*'
# -----------------------------------------------------------------

# Check before running OpenVINS:
#   ros2 topic hz /camera/camera/infra1/image_rect_raw   # expect ~30 Hz
#   ros2 topic hz /camera/camera/imu                     # expect ~400 Hz
#
# Run OpenVINS (stereo):
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d435i \
#        max_cameras:=2 use_stereo:=true rviz_enable:=true
#
# On a weaker machine, run mono to lighten the load:
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d435i \
#        max_cameras:=1 use_stereo:=false rviz_enable:=true
