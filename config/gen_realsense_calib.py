#!/usr/bin/env python3
"""
Sinh file kalibr_imucam_chain.yaml cho OpenVINS tu factory calibration
cua camera RealSense dang cam vao may.

Dung cho D435i / D455 / D457 (moi loai co IMU).

Cach dung:
    python3 config/gen_realsense_calib.py                     # in ra man hinh
    python3 config/gen_realsense_calib.py -o config/rs_d435i/kalibr_imucam_chain.yaml
    python3 config/gen_realsense_calib.py --stream color      # dung RGB thay vi IR
    python3 config/gen_realsense_calib.py --width 1280 --height 720

LUU Y: factory calibration TOT cho intrinsics, nhung extrinsics camera-IMU
thi chi o muc "tam duoc". De co ket quo tot nhat van nen hieu chuan Kalibr.
"""

import argparse
import sys

try:
    import numpy as np
    import pyrealsense2 as rs
except ImportError as e:
    sys.exit("Thieu thu vien: {}\n  pip install pyrealsense2 numpy".format(e))


def fmt_mat4(R, t, indent="    "):
    """In ma tran 4x4 theo dinh dang YAML cua Kalibr."""
    lines = []
    for i in range(3):
        lines.append("{}- [{:.17g}, {:.17g}, {:.17g}, {:.17g}]".format(
            indent, R[i, 0], R[i, 1], R[i, 2], t[i]))
    lines.append("{}- [0.0, 0.0, 0.0, 1.0]".format(indent))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stream", choices=["infra", "color"], default="infra",
                    help="infra = 2 imager IR global shutter (khuyen nghi cho VIO)")
    ap.add_argument("--width", type=int, default=848)
    ap.add_argument("--height", type=int, default=480)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("-o", "--output", default=None)
    args = ap.parse_args()

    # --- Tim thiet bi ---
    ctx = rs.context()
    devices = list(ctx.query_devices())
    if not devices:
        sys.exit("Khong tim thay camera RealSense nao.\n"
                 "  - Kiem tra cap (D435i/D455 can USB3)\n"
                 "  - Chay 'rs-enumerate-devices' de xac nhan\n"
                 "  - D457 dung GMSL, can bo deserializer + kernel driver d4xx")

    dev = devices[0]
    name = dev.get_info(rs.camera_info.name)
    serial = dev.get_info(rs.camera_info.serial_number)
    fw = dev.get_info(rs.camera_info.firmware_version)
    print("# Thiet bi : {}".format(name), file=sys.stderr)
    print("# Serial   : {}".format(serial), file=sys.stderr)
    print("# Firmware : {}".format(fw), file=sys.stderr)

    # --- Bat cac stream can thiet ---
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
        sys.exit("Khong mo duoc stream ({}x{}@{}): {}\n"
                 "  Thu do phan giai khac, vd --width 640 --height 480"
                 .format(args.width, args.height, args.fps, e))

    try:
        # Stream IMU lam goc toa do (accel = goc cua IMU trong librealsense)
        imu_prof = profile.get_stream(rs.stream.accel)

        if args.stream == "infra":
            cams = [("cam0", profile.get_stream(rs.stream.infrared, 1), "infra1"),
                    ("cam1", profile.get_stream(rs.stream.infrared, 2), "infra2")]
        else:
            cams = [("cam0", profile.get_stream(rs.stream.color), "color")]

        out = ["%YAML:1.0", ""]
        out.append("# Sinh tu dong tu factory calibration")
        out.append("# Thiet bi: {}  serial: {}  fw: {}".format(name, serial, fw))
        out.append("# Do phan giai: {}x{} @ {}fps".format(args.width, args.height, args.fps))
        out.append("")

        for idx, (key, sp, label) in enumerate(cams):
            vsp = sp.as_video_stream_profile()
            intr = vsp.get_intrinsics()

            # Extrinsics tu IMU -> camera chinh la T_cam_imu
            extr = imu_prof.get_extrinsics_to(sp)
            # librealsense tra rotation dang COLUMN-MAJOR 9 phan tu
            R = np.array(extr.rotation, dtype=float).reshape(3, 3).T
            t = np.array(extr.translation, dtype=float)

            # Stream ".../image_rect_raw" da rectify -> he so meo = 0
            coeffs = list(intr.coeffs[:4])

            if args.stream == "infra":
                topic = "/camera/camera/{}/image_rect_raw".format(label)
            else:
                topic = "/camera/camera/color/image_raw"

            overlaps = [1 - idx] if len(cams) == 2 else []

            out.append("{}:".format(key))
            out.append("  # {} | model meo: {}".format(label, intr.model))
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
        print("Da ghi: {}".format(args.output), file=sys.stderr)
    else:
        print(text)


if __name__ == "__main__":
    main()
