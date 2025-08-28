#!/usr/bin/env python3

"""
This scripts reads a list of points from stdin (each point on separate line,
either `x, y` or `y` with x auto-incremented) and displays a pyplot graph.
"""

import matplotlib.pyplot as plt
import sys
import re
import getopt

marker = '.'
title = None
x_label = None
y_label = None
start_y_at_zero = False
force_legend_off = False
opts, args = getopt.getopt(sys.argv[1:], 'Llp0t:x:y:')
for o, a in opts:
    if o == '-p': marker = ''
    if o == '-l': marker += '-'
    if o == '-t': title = a
    if o == '-x': x_label = a
    if o == '-y': y_label = a
    if o == '-0': start_y_at_zero = True
    if o == '-L': force_legend_off = True


show_legend = False
x = []
y = []
data_label = None

i = 0
for line in sys.stdin:
  line = line.strip()
  if line.startswith("="):
    if len(x) > 0:
      plt.plot(x, y, marker, label=data_label)
    x = []
    y = []
    data_label = line[1:].strip()
    show_legend = True
    continue

  vals = [float(n.strip()) for n in line.split(",")]
  if len(vals) == 1:
    x.append(i)
    y.append(vals[0])
  else:
    x.append(vals[0])
    y.append(vals[1])
  i += 1

if force_legend_off:
  show_legend = False

if len(x) > 0:
  plt.plot(x, y, marker, label=data_label)

if show_legend:
  plt.legend()
if start_y_at_zero:
  plt.ylim(bottom=0)
plt.title(title)
plt.xlabel(x_label)
plt.ylabel(y_label)

plt.minorticks_on()
plt.grid(which='both', color='#eee')
plt.show()
