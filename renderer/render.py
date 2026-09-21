"""Run inside the installed GIMP 3 Python interpreter, without network access."""

import json
import os
import sys
import traceback
from pathlib import Path

from gi.repository import Gegl, Gimp, Gio
from job import read_job


def export_jpeg(image, path, quality):
    """Export sRGB pixels with a color profile and without camera metadata."""
    procedure = Gimp.get_pdb().lookup_procedure("file-jpeg-export")
    config = procedure.create_config()
    config.set_property("run-mode", Gimp.RunMode.NONINTERACTIVE)
    config.set_property("image", image)
    config.set_property("file", Gio.File.new_for_path(str(path)))
    for name in ("include-exif", "include-iptc", "include-xmp", "include-thumbnail"):
        config.set_property(name, False)
    config.set_property("include-color-profile", True)
    config.set_property("quality", quality)
    if procedure.run(config).index(0) != Gimp.PDBStatusType.SUCCESS:
        raise RuntimeError(f"GIMP could not export {path.name}. Check available disk space.")


def make_layers(image, job):
    """Build a masked artwork layer, background, and hidden cropped reference."""
    image.undo_disable()
    original = image.get_layers()[0]
    original.set_name("Original photo — cropped reference")
    frame = original.copy()
    image.insert_layer(frame, None, 0)
    frame.set_name("Artwork and wood — editable mask")
    original.set_visible(False)
    Gimp.context_set_antialias(True)
    Gimp.context_set_feather(False)
    coordinates = [point[key] for point in job["points"] for key in ("x", "y")]
    image.select_polygon(Gimp.ChannelOps.REPLACE, coordinates)
    Gimp.Selection.feather(image, 1.2)
    frame.add_mask(frame.create_mask(Gimp.AddMaskType.SELECTION))
    Gimp.Selection.none(image)
    width, height = job["canvas"]
    image.resize(width, height, *job["offset"])
    original.resize_to_image_size()
    frame.resize_to_image_size()
    background = Gimp.Layer.new(
        image,
        f"Background — {job['background']}",
        width,
        height,
        Gimp.ImageType.RGB_IMAGE,
        100,
        Gimp.LayerMode.NORMAL,
    )
    image.insert_layer(background, None, 1)
    Gimp.context_set_background(Gegl.Color.new(job["background"]))
    background.fill(Gimp.FillType.BACKGROUND)
    image.set_selected_layers([frame])
    image.undo_enable()


def render(job, folder):
    """Produce the three deliverables, leaving the input file untouched."""
    image = Gimp.file_load(Gimp.RunMode.NONINTERACTIVE, Gio.File.new_for_path(job["input"]))
    if image is None:
        raise RuntimeError("GIMP could not read the normalized source photo.")
    try:
        if (image.get_width(), image.get_height()) != (job["width"], job["height"]):
            raise ValueError("Source dimensions do not match the reviewed outline.")
        make_layers(image, job)
        if not Gimp.file_save(
            Gimp.RunMode.NONINTERACTIVE,
            image,
            Gio.File.new_for_path(str(folder / "artwork.xcf")),
        ):
            raise RuntimeError("Could not save the editable GIMP project.")
        export_copies(image, job, folder)
    finally:
        image.delete()


def export_copies(image, job, folder):
    """Flatten only a copy so the saved XCF retains its layers and editable mask."""
    delivery = image.duplicate()
    try:
        delivery.flatten()
        delivery.convert_color_profile(
            Gimp.ColorProfile.new_rgb_srgb(),
            Gimp.ColorRenderingIntent.RELATIVE_COLORIMETRIC,
            True,
        )
        export_jpeg(delivery, folder / "full.jpg", 0.97)
        Gimp.context_set_interpolation(Gimp.InterpolationType.NOHALO)
        delivery.scale(*job["social"])
        export_jpeg(delivery, folder / "social.jpg", 0.95)
    finally:
        delivery.delete()


def main():
    """Write a structured result even when GIMP itself exits with a misleading success code."""
    path = Path(os.environ["ARTPREP_JOB"])
    try:
        job = read_job(path)
        render(job, path.parent)
        result = {"success": True}
    except Exception as error:
        traceback.print_exc(file=sys.stderr)
        result = {"success": False, "error": str(error)}
    (path.parent / "result.json").write_text(json.dumps(result))


main()
