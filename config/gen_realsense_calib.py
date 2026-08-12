#!/usr/bin/env python3
"""
Generate kalibr_imucam_chain.yaml for OpenVINS from the factory calibration
of the RealSense camera currently plugged into the machine.

Works for D435i / D455 / D457 (all of which have an IMU).

Usage:
    python3 config/gen_realsense_calib.py                     # print to stdout
    python3 config/gen_realsense_calib.py -o config/rs_d435i/kalibr_imucam_chain.yaml
    python3 config/gen_realsense_calib.py --stream color      # use RGB instead of IR
    python3 config/gen_realsense_calib.py --width 1280 --height 720

NOTE: the factory calibration is GOOD for intrinsics, but the camera-IMU
extrinsics are only "just about acceptable". For best results, still run a
Kalibr calibration.
"""

import argparse
import sys

try:
    import numpy as np
    import pyrealsense2 as rs
except ImportError as e:
    sys.exit("Missing library: {}\n  pip install pyrealsense2 numpy".format(e))


def fmt_mat4(R, t, indent="    "):
    """Print a 4x4 matrix in Kalibr's YAML format."""
    lines = []
    for i in range(3):
        lines.append("{}- [{:.17g}, {:.17g}, {:.17g}, {:.17g}]".format(
            indent, R[i, 0], R[i, 1], R[i, 2], t[i]))
    lines.append("{}- [0.0, 0.0, 0.0, 1.0]".format(indent))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stream", choices=["infra", "color"], default="infra",
                    help="infra = the 2 global-shutter IR imagers (recommended for VIO)")
    ap.add_argument("--width", type=int, default=848)
    ap.add_argument("--height", type=int, default=480)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("-o", "--output", default=None)
    args = ap.parse_args()

    # --- Find the device ---
    ctx = rs.context()
    devices = list(ctx.query_devices())
    if not devices:
        sys.exit("No RealSense camera found.\n"
                 "  - Check the cable (D435i/D455 need USB3)\n"
                 "  - Run 'rs-enumerate-devices' to confirm\n"
                 "  - The D457 uses GMSL and needs a deserializer board + the d4xx kernel driver")

    dev = devices[0]
    name = dev.get_info(rs.camera_info.name)
    serial = dev.get_info(rs.camera_info.serial_number)
    fw = dev.get_info(rs.camera_info.firmware_version)
    print("# Device   : {}".format(name), file=sys.stderr)
    print("# Serial   : {}".format(serial), file=sys.stderr)
    print("# Firmware : {}".format(fw), file=sys.stderr)

    # --- Enable the required streams ---
    cfg = rs.config()
    cfg.enable_device(serial)
    if args.stream == "infra":
        cfg.enable_stream(rs.stream.infrared, 1, args.width, args.height, rs.format.y8, args.fps)
        cfg.enable_stream(rs.stream.infrared, 2, args.width, args.height, rs.format.y8, args.fps)
    else:
        cfg.enable_stream(rs.stream.color, args.width, args.height, rs.format.bgr8, args.fps)
    cfg.enable_stream(rs.stream.accel)
    cfg.enable_stream(rs.stream.gyro)

    pipe = rs.pipeline(ctx)
    try:
        profile = pipe.start(cfg)
    except RuntimeError as e:
        sys.exit("Could not open the stream ({}x{}@{}): {}\n"
                 "  Try another resolution, e.g. --width 640 --height 480"
                 .format(args.width, args.height, args.fps, e))

    try:
        # Use the IMU stream as the frame origin (accel = the IMU origin in librealsense)
        imu_prof = profile.get_stream(rs.stream.accel)

        if args.stream == "infra":
            cams = [("cam0", profile.get_stream(rs.stream.infrared, 1), "infra1"),
                    ("cam1", profile.get_stream(rs.stream.infrared, 2), "infra2")]
        else:
            cams = [("cam0", profile.get_stream(rs.stream.color), "color")]

        out = ["%YAML:1.0", ""]
        out.append("# Auto-generated from factory calibration")
        out.append("# Device: {}  serial: {}  fw: {}".format(name, serial, fw))
        out.append("# Resolution: {}x{} @ {}fps".format(args.width, args.height, args.fps))
        out.append("")

        for idx, (key, sp, label) in enumerate(cams):
            vsp = sp.as_video_stream_profile()
            intr = vsp.get_intrinsics()

            # The extrinsics from IMU -> camera are exactly T_cam_imu
            extr = imu_prof.get_extrinsics_to(sp)
            # librealsense returns the rotation as 9 elements in COLUMN-MAJOR order
            R = np.array(extr.rotation, dtype=float).reshape(3, 3).T
            t = np.array(extr.translation, dtype=float)

            # The ".../image_rect_raw" stream is already rectified -> distortion coeffs = 0
            coeffs = list(intr.coeffs[:4])

            if args.stream == "infra":
                topic = "/camera/camera/{}/image_rect_raw".format(label)
            else:
                topic = "/camera/camera/color/image_raw"

            overlaps = [1 - idx] if len(cams) == 2 else []

            out.append("{}:".format(key))
            out.append("  # {} | distortion model: {}".format(label, intr.model))
            out.append("  T_cam_imu:")
            out.append(fmt_mat4(R, t))
            out.append("  cam_overlaps: {}".format(overlaps))
            out.append("  camera_model: pinhole")
            out.append("  distortion_coeffs: [{}]".format(
                ", ".join("{:.17g}".format(c) for c in coeffs)))
            out.append("  distortion_model: radtan")
            out.append("  intrinsics: [{:.17g}, {:.17g}, {:.17g}, {:.17g}] # fx, fy, cx, cy".format(
                intr.fx, intr.fy, intr.ppx, intr.ppy))
            out.append("  resolution: [{}, {}]".format(intr.width, intr.height))
            out.append("  rostopic: {}".format(topic))
            out.append("  timeshift_cam_imu: 0.0")
            out.append("")

        text = "\n".join(out)
    finally:
        pipe.stop()

    if args.output:
        with open(args.output, "w") as f:
            f.write(text)
        print("Written: {}".format(args.output), file=sys.stderr)
    else:
        print(text)


if __name__ == "__main__":
    main()
