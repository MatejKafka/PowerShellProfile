#!/usr/bin/env python3

"""
This scripts reads a list of points from stdin (each point on separate line,
either `x, y` or `y` with x auto-incremented) and displays a pyplot graph.
"""

import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import sys
import getopt
import json
import datetime

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
has_date = False

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

  vals = json.loads(line)
  if isinstance(vals, list) and len(vals) == 2:
    key, value = vals
  else:
    key, value = i, vals
  i += 1

  try:
    key = datetime.datetime.fromisoformat(key)
    has_date = True
  except:
    pass

  x.append(key)
  y.append(value)

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

if has_date:
  locator = mdates.AutoDateLocator(minticks=3, maxticks=7)
  formatter = mdates.ConciseDateFormatter(locator)
  ax = plt.gca()
  ax.xaxis.set_major_locator(locator)
  ax.xaxis.set_major_formatter(formatter)
else:
  plt.minorticks_on()

plt.grid(which='both', color='#eee')
plt.show()
