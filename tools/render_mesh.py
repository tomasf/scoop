"""CPU preview for environments where Cadova Viewer's Metal renderer is unavailable.

Requires numpy and Pillow. Usage: python3 tools/render_mesh.py model.3mf output.png [top|side|section]
"""
import sys
import zipfile
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image, ImageDraw

source, output = sys.argv[1:3]
view = sys.argv[3] if len(sys.argv) > 3 else "iso"
with zipfile.ZipFile(source) as archive:
    root = ET.fromstring(archive.read("3D/3dmodel.model"))
ns = {"m": "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"}
vertices, triangles = [], []
for mesh in root.findall(".//m:mesh", ns):
    start = len(vertices)
    vertices.extend([[float(v.get(k)) for k in ("x", "y", "z")]
                     for v in mesh.findall("m:vertices/m:vertex", ns)])
    triangles.extend([[int(t.get(k)) + start for k in ("v1", "v2", "v3")]
                      for t in mesh.findall("m:triangles/m:triangle", ns)])
points = np.array(vertices)
faces = np.array(triangles)
if view == "section":
    # True plane intersection at y=0. Fill alternating spans through its boundary.
    segments = []
    for triangle in points[faces]:
        crossings = []
        for a, b in zip(triangle, np.roll(triangle, -1, axis=0)):
            if (a[1] >= 0) != (b[1] >= 0):
                p = a + (b - a) * (-a[1] / (b[1] - a[1]))
                crossings.append(p[[0, 2]])
        if len(crossings) == 2 and np.linalg.norm(crossings[0] - crossings[1]) > 1e-8:
            segments.append(crossings)
    segments = np.array(segments)
    segments[:, :, 1] *= -1
    low = segments.min((0, 1)); high = segments.max((0, 1))
    scale = min(1420 / (high[0] - low[0]), 990 / (high[1] - low[1]))
    segments = (segments - (low + high) / 2) * scale + [800, 600]
    image = Image.new("RGB", (1600, 1200), "#f5f3ee")
    draw = ImageDraw.Draw(image)
    a, b = segments[:, 0], segments[:, 1]
    for x in range(1600):
        use = ((a[:, 0] <= x + .5) & (b[:, 0] > x + .5)) | ((b[:, 0] <= x + .5) & (a[:, 0] > x + .5))
        aa, bb = a[use], b[use]
        ys = np.sort(aa[:, 1] + (bb[:, 1] - aa[:, 1]) * (x + .5 - aa[:, 0]) / (bb[:, 0] - aa[:, 0]))
        ys = ys[np.r_[True, np.diff(ys) > .001]] if len(ys) else ys
        for top, bottom in zip(ys[::2], ys[1::2]):
            draw.line((x, int(np.ceil(top)), x, int(np.floor(bottom))), fill="#bc7250")
    image.resize((1000, 750), Image.Resampling.LANCZOS).save(output)
    sys.exit(0)
camera = np.array({"top": [0, 0, 1], "side": [0, -1, 0],
                   "iso": [0.65, -1.3, 1.45]}.get(view, [-0.6, 1, 1.2]), dtype=float)
camera /= np.linalg.norm(camera)
right = np.cross([0, 1, 0] if view == "top" else [0, 0, 1], camera)
right /= np.linalg.norm(right)
up = np.cross(camera, right)
screen = np.column_stack((points @ right, -(points @ up)))
depth = points @ camera
scale = min(1420 / np.ptp(screen[:, 0]), 990 / max(np.ptp(screen[:, 1]), 1))
screen = (screen - (screen.min(0) + screen.max(0)) / 2) * scale + [800, 600]
image = Image.new("RGB", (1600, 1200), "#f5f3ee")
pixels = np.array(image)
zbuffer = np.full((1200, 1600), -np.inf)
normals = np.cross(points[faces[:, 1]] - points[faces[:, 0]],
                   points[faces[:, 2]] - points[faces[:, 0]])
lengths = np.linalg.norm(normals, axis=1)
normals /= np.maximum(lengths[:, None], 1e-12)
light = np.array([-0.3, -0.5, 0.9]); light /= np.linalg.norm(light)
brightness = 0.46 + 0.54 * np.maximum(normals @ light, 0)
base = np.array([48, 145, 152])
for index, face in enumerate(faces):
    if normals[index] @ camera <= 0:
        continue
    triangle = screen[face]
    low = np.maximum(np.floor(triangle.min(0)).astype(int), [0, 0])
    high = np.minimum(np.ceil(triangle.max(0)).astype(int), [1599, 1199])
    if np.any(high < low):
        continue
    a, b, c = triangle
    denominator = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
    if abs(denominator) < 1e-10:
        continue
    xx, yy = np.meshgrid(np.arange(low[0], high[0] + 1) + 0.5,
                         np.arange(low[1], high[1] + 1) + 0.5)
    u = ((b[1] - c[1]) * (xx - c[0]) + (c[0] - b[0]) * (yy - c[1])) / denominator
    v = ((c[1] - a[1]) * (xx - c[0]) + (a[0] - c[0]) * (yy - c[1])) / denominator
    w = 1 - u - v
    z = u * depth[face[0]] + v * depth[face[1]] + w * depth[face[2]]
    region = np.s_[low[1]:high[1] + 1, low[0]:high[0] + 1]
    visible = (u >= -1e-8) & (v >= -1e-8) & (w >= -1e-8) & (z > zbuffer[region])
    zbuffer[region][visible] = z[visible]
    pixels[region][visible] = (base * brightness[index]).astype(np.uint8)
image = Image.fromarray(pixels)
image.resize((1000, 750), Image.Resampling.LANCZOS).save(output)
