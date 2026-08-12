#!/usr/bin/env bash
# =====================================================================
# Bring up a RealSense D455 for OpenVINS on ROS 2 Jazzy
# Validated device: Intel RealSense D455, serial 351322306551, FW 5.17.0.10
# =====================================================================
#
# !!! HARD REQUIREMENT: MUST BE PLUGGED INTO A USB 3.x PORT !!!
#
# Check before running:
#     rs-enumerate-devices -s
#     python3 -c "import pyrealsense2 as rs; \
#       print(list(rs.context().query_devices())[0].get_info(rs.camera_info.usb_type_descriptor))"
#
# This must print "3.2". If it prints "2.1", STOP - on USB 2.1:
#     - Only ONE IR stream (infra1) exists. infra2 is MISSING -> no stereo.
#     - 848x480@30 is unavailable (only 848x480@5 or @10 remain).
# Move to a high-speed USB-C port and use the USB3 cable shipped with the unit.

set -e

# --- Check bandwidth before launching ---
USB=$(python3 -c "
import pyrealsense2 as rs
d=list(rs.context().query_devices())
print(d[0].get_info(rs.camera_info.usb_type_descriptor) if d else 'NO_DEVICE')
" 2>/dev/null || echo "UNKNOWN")

echo "Detected USB type: $USB"
if [ "$USB" = "NO_DEVICE" ]; then
  echo "ERROR: no camera found. Check the cable." >&2
  exit 1
fi
if [ "${USB%%.*}" = "2" ]; then
  echo "WARNING: running on USB $USB -> not enough bandwidth for stereo 848x480@30." >&2
  echo "         Move to a USB 3.x port before running OpenVINS." >&2
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
# ON MOTION BLUR
#
# Measured from real frame metadata (not from the default parameters):
#       actual_exposure = 19946 us = ~20 ms  !!!
# With fx = 433 px, one degree spans ~7.56 pixels, so the blur streak is:
#       blur_px = fx * omega(rad/s) * t_exposure
#   At 20ms:  115 deg/s -> 17 px | 285 deg/s -> 43 px | 570 deg/s -> 87 px
#   At  3ms:  115 deg/s ->  3 px | 285 deg/s ->  6 px | 570 deg/s -> 13 px
# min_px_dist = 15, so at 20ms even moderate shaking makes KLT lose track.
#
# NOTE: the auto_exposure_limit approach does NOT work on this D455
# (tested: set limit=3000 but actual_exposure stayed at 19946).
# Auto-exposure must be turned OFF and the value set manually to take effect.
# Trade-off: darker image -> gain must go up (64) -> slightly more noise.
# Noise is MUCH more tolerable than blur: noise only makes features less
# accurate, whereas blur DESTROYS them outright.
#
# If the room is too dark, try:
#   - Raising gain to 48-64
#   - Or relaxing the limit to 4000-5000us
#   - Or adding light (the IR image responds to daylight and halogen lamps)
# -----------------------------------------------------------------

# Once the driver is running, in another terminal:
#   python3 config/gen_realsense_calib.py -o config/rs_d455/kalibr_imucam_chain.yaml
#   ros2 launch ov_msckf subscribe.launch.py config:=rs_d455 \
#        max_cameras:=2 use_stereo:=true rviz_enable:=true
