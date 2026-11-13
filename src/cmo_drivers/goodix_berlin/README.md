# Goodix Berlin driver

`goodix_berlin_core.c` was missing from this source package even though the
Makefile builds it. It was restored from the GPL-2.0-or-later Linux v6.14 source:

https://github.com/torvalds/linux/blob/v6.14/drivers/input/touchscreen/goodix_berlin_core.c

Before modification, building that source with this directory's header reproduced
the installed module's `srcversion`, `E391E3774E3F06A1A668049`.

The local change retries a complete event up to three times when its header or
contact checksum is invalid. Only a fully validated event reaches the input layer.
An unrecoverable event is still discarded and reported; acknowledgement errors
are also reported. No checksum formula or coordinate format was changed.

Read-only counters on the I2C device expose transport recovery:

- `checksum_retries`: additional event reads requested after invalid checksums.
- `checksum_recovered`: valid events obtained after a retry.
- `checksum_failures`: events that could not be recovered, including events that
  disappeared before a valid read.

The CM0 panel overlay uses open-drain GPIO flags and a 5 us bit delay for
approximately 100 kHz I2C, avoiding the much longer reads caused by a 40 us delay.

Example cross-build against matching ARMv7 kernel headers:

```sh
make -C /usr/src/linux-headers-6.12.34+rpt-rpi-v7 \
  M="$PWD" ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- W=1 modules
```
