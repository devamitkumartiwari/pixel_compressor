// ignore_for_file: constant_identifier_names

abstract class const PixelMediaEnum<T>(this._value) {
  final T _value;

  T get value => _value;
}

// ignore: avoid_types_as_parameter_names
class const PixelMediaMetadataKey<int>(super.value)
    extends PixelMediaEnum<int> {
  /// Android: API level 10
  static const METADATA_KEY_ALBUM = PixelMediaMetadataKey(1);

  /// Android: API level 10
  static const METADATA_KEY_ALBUMARTIST = PixelMediaMetadataKey(13);

  /// Android: API level 10
  static const METADATA_KEY_ARTIST = PixelMediaMetadataKey(2);

  /// Android: API level 10
  static const METADATA_KEY_AUTHOR = PixelMediaMetadataKey(3);

  /// Android: API level 14
  static const METADATA_KEY_BITRATE = PixelMediaMetadataKey(20);

  /// Android: API level 23
  static const METADATA_KEY_CAPTURE_FRAMERATE = PixelMediaMetadataKey(25);

  /// Android: API level 10
  static const METADATA_KEY_CD_TRACK_NUMBER = PixelMediaMetadataKey(0);

  /// Android: API level 10
  static const METADATA_KEY_COMPILATION = PixelMediaMetadataKey(15);

  /// Android: API level 10
  static const METADATA_KEY_COMPOSER = PixelMediaMetadataKey(4);

  /// Android: API level 10
  static const METADATA_KEY_DATE = PixelMediaMetadataKey(5);

  /// Android: API level 10
  static const METADATA_KEY_DISC_NUMBER = PixelMediaMetadataKey(14);

  /// Android: API level 10
  static const METADATA_KEY_DURATION = PixelMediaMetadataKey(9);

  /// Android: API level Q
  static const METADATA_KEY_EXIF_LENGTH = PixelMediaMetadataKey(34);

  /// Android: API level Q
  static const METADATA_KEY_EXIF_OFFSET = PixelMediaMetadataKey(33);

  /// Android: API level 10
  static const METADATA_KEY_GENRE = PixelMediaMetadataKey(6);

  /// Android: API level 14
  static const METADATA_KEY_HAS_AUDIO = PixelMediaMetadataKey(16);

  /// Android: API level 28
  static const METADATA_KEY_HAS_IMAGE = PixelMediaMetadataKey(26);

  /// Android: API level 14
  static const METADATA_KEY_HAS_VIDEO = PixelMediaMetadataKey(17);

  /// Android: API level 28
  static const METADATA_KEY_IMAGE_COUNT = PixelMediaMetadataKey(27);

  /// Android: API level 28
  static const METADATA_KEY_IMAGE_HEIGHT = PixelMediaMetadataKey(30);

  /// Android: API level 28
  static const METADATA_KEY_IMAGE_PRIMARY = PixelMediaMetadataKey(28);

  /// Android: API level 28
  static const METADATA_KEY_IMAGE_ROTATION = PixelMediaMetadataKey(31);

  /// Android: API level 28
  static const METADATA_KEY_IMAGE_WIDTH = PixelMediaMetadataKey(29);

  /// Android: API level 15
  static const METADATA_KEY_LOCATION = PixelMediaMetadataKey(23);

  /// Android: API level 10
  static const METADATA_KEY_MIMETYPE = PixelMediaMetadataKey(12);

  /// Android: API level 10
  static const METADATA_KEY_NUM_TRACKS = PixelMediaMetadataKey(10);

  /// Android: API level 10
  static const METADATA_KEY_TITLE = PixelMediaMetadataKey(7);

  /// Android: API level 28
  static const METADATA_KEY_VIDEO_FRAME_COUNT = PixelMediaMetadataKey(32);

  /// Android: API level 14
  static const METADATA_KEY_VIDEO_HEIGHT = PixelMediaMetadataKey(19);

  /// Android: API level 17
  static const METADATA_KEY_VIDEO_ROTATION = PixelMediaMetadataKey(24);

  /// Android: API level 14
  static const METADATA_KEY_VIDEO_WIDTH = PixelMediaMetadataKey(18);

  /// Android: API level 10
  static const METADATA_KEY_WRITER = PixelMediaMetadataKey(11);

  /// Android: API level 10
  static const METADATA_KEY_YEAR = PixelMediaMetadataKey(8);
}
