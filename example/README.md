# pixel_compressor example

A demo app for every pixel_compressor API, in seven tabs:

| Tab | Shows |
|---|---|
| **Image** | JPEG, PNG, WebP and HEIC compression with resizing, rotation and EXIF options |
| **Batch** | Compressing many files at once with limited concurrency |
| **Inspect** | An image's size, format and orientation, read without compressing |
| **Video** | H.264 / HEVC compression with trimming, resizing, bitrate and audio settings |
| **Thumbnails** | JPEG frames at exact positions, as bytes or files |
| **Merge** | Strips and grids of images, with a live preview |
| **Tools** | Platform support, validation, logging and cache controls |

Three sample images in `assets/samples/` let you try every image feature without picking a file. For your own media it uses `wechat_assets_picker` on Android, iOS and macOS, and the browser's file dialog on the web.

## Run

```sh
flutter run
```

## Integration test

`integration_test/app_test.dart` drives every tab with the samples (real native compression) in a phone layout and a wide layout, and saves screenshots:

```sh
flutter test integration_test -d <device-id>
```

On macOS, keep the app window visible while the test runs. A hidden window doesn't draw frames, so the test stalls.
