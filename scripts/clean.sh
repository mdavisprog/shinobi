#!/bin/bash

pushd "$(dirname "${BASH_SOURCE[0]}")"
pushd ..

DIRS=(
    .zig-cache
    zig-out
    examples/plutovg/.zig-cache
    examples/plutovg/zig-out
    examples/plutovg/external/plutovg/Build
)

for DIR in "${DIRS[@]}"
do
    if [  -d "$DIR" ] ; then
        echo "Cleaning directory $DIR"
        rm -rf $DIR
    fi
done

popd
popd
