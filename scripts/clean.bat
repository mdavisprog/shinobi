@ECHO OFF

SETLOCAL ENABLEDELAYEDEXPANSION
PUSHD "%~dp0"
PUSHD ..

SET CACHE=.zig-cache
SET OUT=zig-out

SET DIRS=%CACHE%^
    %OUT%^
    "examples/plutovg/%CACHE%"^
    "examples/plutovg/%OUT%"

ECHO Cleaning...
FOR %%A in (%DIRS%) do (
    IF EXIST %%A (
        ECHO Cleaning %%A
        RMDIR /S /Q %%A
    )
)

POPD
POPD
ENDLOCAL
