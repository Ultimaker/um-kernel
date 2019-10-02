#!/usr/bin/env python2
#
# convertfb - program to adapt image to framebuffer
#
#
# This program is provided under the Gnu General Public License (GPL)
# version 2 ONLY. This program is distributed WITHOUT ANY WARRANTY.
# See the LICENSE file, which should have accompanied this program,
# for the text of the license.
#
# 2016-11-27 by zqb-all <zhuangqiubin@gmail.com>
#
#
# CHANGELOG:
#  2016.11.27 - Version 1.0.0 - The first version

VERSION=(1,0,0)

import argparse
from PIL import Image
import struct
parser = argparse.ArgumentParser()
parser.add_argument('-i' , '--input' , dest='img_in'    , metavar='IMAGE' , help="image to handle" , default='demo.bmp')
parser.add_argument('-o' , '--output', dest='img_out'   , metavar='IMAGE' , help="image to fb"     , default='demo.fb')
parser.add_argument('-bw', '--width' , dest='buf_width' , metavar='WIDTH' , help="width of buffer" , type=int)
parser.add_argument('-bh', '--height', dest='buf_height', metavar='HEIGHT', help="height of buffer", type=int)
parser.add_argument('-f' , '--format', dest='format'    , metavar='FORMAT', help="format,RGB,BGR,ARGB...",default='RGB')

args = parser.parse_args()

args.format = args.format.upper()

im = Image.open(args.img_in).convert("RGBA")
w, h = im.size

pixels={'A':0,'R':0,'G':0,'B':0}

#if not define the size of framebuffer,use the size of image
if(args.buf_width==None):
	args.buf_width = w
if(args.buf_height==None):
	args.buf_height = h



print 'Image:',args.img_in,' ',w,'X',h,im.mode
print 'FrameBuffer:',args.buf_width,'X',args.buf_height,args.format


#if the size of image larger than than the framebuffer,cut it
if(w > args.buf_width):
	w = args.buf_width
	print 'cut the Image width to',args.buf_width

if(h > args.buf_width):
 	h = args.buf_height
	print 'cut the Image height to',args.buf_width


with open(args.img_out, 'wb') as f:
    for j in range(0,h):
        for i in range(0,w):
            pixels['R'],pixels['G'],pixels['B'],pixels['A']=im.getpixel((i,j))
            for n in args.format:
                f.write(struct.pack('B',pixels[n]))
        #if the image smaller than the framebuffer,fill in 0
        for i in range(w,args.buf_width):
            for n in args.format:
            	f.write(struct.pack('B',0))


