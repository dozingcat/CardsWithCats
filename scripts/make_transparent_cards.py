import os
import sys

from PIL import Image


# "Removes" white background by adding as much transparency as possible while
# keeping the same result when drawing the image on top of solid white.
# Solid white becomes fully transparent, solid black is unchanged.
# Examples (rgba components in [0,1]):
#   red=1, green=0.5, blue=0.5 => red=1, green=0, blue=0, alpha=0.5
#   red=1, green=0.5, blue=0.25 => red=1, green=1/3, blue=0, alpha=0.75
#   red=1, green=1, blue=1 => alpha=0, rgb=<anything>
def convert(input_file: str, output_file: str):
    src = Image.open(input_file)
    src_pixels = src.load()
    width = src.width
    height = src.height
    dst = Image.new('RGBA', (width, height))
    dst_pixels = dst.load()
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = src_pixels[x, y]
            if alpha < 1:
                dst_pixels[x, y] = (red, green, blue, alpha)
                continue
            # Take RGB inverses and normalize to [0, 1]
            rneg = 1 - red / 255
            bneg = 1 - blue / 255
            gneg = 1 - green / 255
            # Alpha is the maximum inverse value.
            af = max(rneg, bneg, gneg)
            if (af == 0):
                dst_pixels[x, y] = (0, 0, 0, 1)
                continue
            # The component with maximum inverse will have an output inverse
            # component of 1, so that when it's blended with white
            # (whose inverse is 0), the result will be the original input.
            out_rneg = rneg / af
            out_bneg = bneg / af
            out_gneg = gneg / af
            out_red = round(255 * (1 - out_rneg))
            out_green = round(255 * (1 - out_gneg))
            out_blue = round(255 * (1 - out_bneg))
            out_alpha = round(255 * af)
            dst_pixels[x, y] = (out_red, out_green, out_blue, out_alpha)
    dst.save(output_file, "webp")


# Converts all images in the directory `args[1]`` whose filenames match "??.*"
# (e.g. card images like "AS.webp"). Writes converted images to the directory `args[2]`.
def main(args):
    input_dir = args[1]
    output_dir = args[2]
    files = os.listdir(input_dir)
    for f in files:
        if len(f.split('.')[0]) == 2:
            input_file = os.path.join(input_dir, f)
            output_file = os.path.join(output_dir, f)
            print(f'Converting {f}')
            convert(input_file, output_file)


if __name__ == '__main__':
    main(sys.argv)
