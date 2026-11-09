Thanks for the report, it was a real bug! Your own scenes only worked while standing still, so flying ended the camera (or never started it), mouse steering stopped the zoom-back, and your hide rules dropped once you moved. It's fixed in the latest update (2.0.9).

To get the zoom-out: make your own scene with State trigger "Mounted", Until "ends", and this script as its camera (Scripts page > Import > paste > Add script). It zooms all the way out and back after you land:

```
CINES1:e3M0OmRlc2NzODk6Wm9vbXMgYWxsIHRoZSB3YXkgb3V0IHdoaWxlIHlvdSByaWRlIG9yIGZseSwgYW5kIGJhY2sgdG8geW91ciBvd24gZGlzdGFuY2Ugd2hlbiB5b3UgbGFuZC5zNjplbmRpbmd7bjE7e3MxOmtzNzpwdXRiYWNrczQ6c2Vjc24yLjU7czQ6em9vbXMzOnllc319czQ6aWNvbnMzNjpJbnRlcmZhY2VcSWNvbnNcSU5WX01pc2NfU3B5Z2xhc3NfMDNzNDpuYW1lczE0OlNreXJpZGluZyB6b29tczU6cnVsZXN7czY6Y2FtZXJhczU6cGF1c2VzMTA6Y2FtZXJhU2Vjc24zO3M0OmVuZHNzNzpwdXRiYWNrczU6ZmlnaHRzNzpwdXRiYWNrczQ6d2Fsa3M2Omlnbm9yZXM0Onpvb21zNjppZ25vcmV9czU6c3RlcHN7bjE7e3M0OmVhc2VzNjpnZW50bGVzMzpmaXRzNDpzZWNzczE6a3M0Onpvb21zMjpvZnM1OnlhcmRzczQ6cGFzdHMzOnllc3M0OnNlY3NuMztzNTpzcGVlZG4wO3MyOnRvbjM5O319fTFiMTRhM2Yy
```

To hide things while flying, use the "mounted" rule word. We're also working on a more advanced skyriding camera that reacts to your speed and climbing or diving.
