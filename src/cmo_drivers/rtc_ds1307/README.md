# RTC DS1307 family / Epson RX8130

Baseline: Linux stable v6.12.34, GPL-2.0-or-later:
https://github.com/gregkh/linux/blob/v6.12.34/drivers/rtc/rtc-ds1307.c

Built unmodified against the CM0 kernel headers, this source reproduces
the installed module's srcversion: `81B86FDF5BB469055BC711C`.

RX8130 stores weekday as a one-hot bit mask. Linux `struct rtc_time.tm_wday`
uses Sunday=0 through Saturday=6. `fls()` returns 1 through 7, so decoding
requires subtracting one. Without it, reading and writing a time advances
the weekday. The change only corrects RX8130 weekday decoding; I2C failures
remain reported and are not hidden by retries or log filtering.

Build with matching kernel headers:

```sh
make -C /usr/src/linux-headers-6.12.34+rpt-rpi-v7 \
  M="$PWD" ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- W=1 KCFLAGS=-Werror modules
```
