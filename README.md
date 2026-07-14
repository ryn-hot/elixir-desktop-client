# Elixir Desktop Client (Qt 6 + QML + QTMPV)

This is the Qt 6/QML rewrite of the Elixir desktop client. It speaks to the Rust server over HTTP and uses QTMPV (libmpv) for playback.

## Prerequisites

- Qt 6.5+ (Core, Gui, Qml, Quick, QuickControls2, Network, Test, QuickTest)
- libmpv + KDE/mpvqt (Qt 6 wrapper)

## Build

```
mkdir -p build
cd build
cmake ..
cmake --build .
```

## Tests

CTest includes deterministic C++ scheduler/network fixtures, QML tests, and the
client authentication transport tests:

```sh
cmake -S . -B build -DBUILD_TESTING=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

For an LLVM source-coverage report, use a separate Clang build:

```sh
cmake -S . -B build-coverage -DBUILD_TESTING=ON -DELIXIR_ENABLE_CLIENT_COVERAGE=ON
cmake --build build-coverage --target elixir-client-coverage
```

## Run

```
./elixir-client
```

## macOS packaging (macdeployqt)

```
./scripts/package_macos.sh build
```

Pass a custom app bundle path if needed:

```
./scripts/package_macos.sh build /path/to/elixir-client.app
```

## mpvqt (Qt 6) install on macOS (Homebrew)

```
brew install qt@6 cmake ninja pkg-config extra-cmake-modules mpv
git clone https://github.com/KDE/mpvqt.git
cmake -S mpvqt -B mpvqt/build \
  -DCMAKE_PREFIX_PATH="$(brew --prefix qt@6)" \
  -DCMAKE_INSTALL_PREFIX="$(brew --prefix qt@6)" \
  -DLibmpv_INCLUDE_DIRS="$(brew --prefix mpv)/include"
cmake --build mpvqt/build
cmake --install mpvqt/build
```

Then build this client with `CMAKE_PREFIX_PATH` pointing at your Qt 6 install.
