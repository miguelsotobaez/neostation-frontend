// Relative import to be able to reuse the C sources.
// See the comment in ../flutter_chd.podspec for more information.
//
// libchdr's own amalgamation pulls in its sources and its three vendored
// dependencies, so there is only ever one line to keep in step here.
#include "../../src/flutter_chd.c"
#include "../../src/libchdr/unity.c"
