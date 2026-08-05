# Flutter geolocator plugin

The Flutter geolocator plugin is built following the federated plugin architecture. A detailed explanation of the federated plugin concept can be found in the [Flutter documentation](https://flutter.dev/docs/development/packages-and-plugins/developing-packages#federated-plugins). This means the geolocator plugin is separated into the following packages:

1. [`geolocator`][1]: the app facing package. This is the package users depend on to use the plugin in their project. For details on how to use the [`geolocator`][1] plugin you can refer to its [README.md][2] file.
2. [`geolocator_android`][3]: this package contains the endorsed Android implementation of the geolocator_platform_interface and adds Android support to the [`geolocator`][1] app facing package. More information can be found in its [README.md][4] file;
3. [`geolocator_apple`][5]: this package contains the endorsed iOS and macOS implementations of the geolocator_platform_interface and adds iOS and macOS support to the [`geolocator`][1] app facing package. More information can be found in its [README.md][6] file;
4. [`geolocator_platform_interface`][7]: this package declares the interface which all platform packages must implement to support the app-facing package. Instructions on how to implement a platform package can be found in the [README.md][8] of the [`geolocator_platform_interface`][7] package.

[1]: ./geolocator
[2]: ./geolocator/README.md
[3]: ./geolocator_android
[4]: ./geolocator_android/README.md
[5]: ./geolocator_apple
[6]: ./geolocator_apple/README.md
[7]: ./geolocator_platform_interface
[8]: ./geolocator_platform_interface/README.md
