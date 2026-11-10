@echo off
setlocal

REM Build netiso.xex with the Xbox 360 SDK command-line tools, no Visual Studio needed.
REM Same shape as InvoxiPlayGames' build_plugin.bat; the flags come from netiso.vcxproj
REM (Release|Xbox 360) and xkelib.vcxproj. Untested here: no SDK on the machine that wrote it.
REM
REM Requires: XEDK set by the SDK installer (e.g. C:\Program Files (x86)\Microsoft Xbox 360 SDK)
REM           xextool on PATH for the retail conversion (skipped if missing)
REM Usage:    build_plugin.bat [SDK version: 20871 ^| 21119 ^| 21173 ^| 21250 ^| 21256 (default)]
REM Output:   netiso.xex next to this script; intermediates in build\

set OUTNAME=netiso
set BUILD_DIR=build
set XKEVER=%1
if "%XKEVER%"=="" set XKEVER=21256

if "%XEDK%"=="" (
  echo XEDK is not set. Install the Xbox 360 SDK or set XEDK to its folder.
  exit /b 1
)

set INCLUDE=%XEDK%\include\xbox
set LIB=%XEDK%\lib\xbox
set BINARYPATH=%XEDK%\bin\win32

pushd "%~dp0"
mkdir %BUILD_DIR% 2>NUL

REM 1. Import libraries for the kernel and XAM exports xkelib declares (xkelib.vcxproj pre-build).
REM    netiso links them through #pragma comment(lib, "kernelext") / "xamext" in the xkelib headers.
echo Creating xkelib import libs for SDK %XKEVER%...
"%BINARYPATH%\lib.exe" /nologo /def:xkelib\xam\xamext%XKEVER%.0.def /MACHINE:PPCBE /OUT:xkelib\xamext.lib || goto :fail
"%BINARYPATH%\lib.exe" /nologo /def:xkelib\kernel\kernelext%XKEVER%.0.def /MACHINE:PPCBE /OUT:xkelib\kernelext.lib || goto :fail

REM 2. Compile as C: full optimisation for size, string pooling, function-level linking,
REM    no exceptions, no /GS, static CRT, NDEBUG + _XBOX, xkelib on the include path.
echo Compiling...
"%BINARYPATH%\cl.exe" /c /nologo /Zi /W3 /Ox /Os /GF /Gy /GS- /MT /D NDEBUG /D _XBOX /I xkelib /TC ^
  /Fo"%BUILD_DIR%/" /Fd"%BUILD_DIR%/" ^
  netiso\client.c netiso\dvdHook.c netiso\fsdDriver.c netiso\hooks.c netiso\irpCompare.c ^
  netiso\isoio.c netiso\main.c netiso\utility.c netiso\vtray.c || goto :fail

REM 3. Link as a DLL image. /XEX:NO keeps the SDK linker from running imagexex itself.
echo Linking...
"%BINARYPATH%\link.exe" /nologo /DLL /OUT:"%BUILD_DIR%\%OUTNAME%.dll" ^
  /ENTRY:_DllMainCRTStartup /INCLUDE:XboxKrnlBuildNumber /ALIGN:128,4096 /DEF:netiso\netiso.def ^
  /LIBPATH:xkelib xapilib.lib xboxkrnl.lib libcmt.lib xnet.lib ^
  /OPT:REF /OPT:ICF /RELEASE /DEBUG /PDB:"%BUILD_DIR%\%OUTNAME%.pdb" /MAP:"%BUILD_DIR%\%OUTNAME%.map" /XEX:NO ^
  "%BUILD_DIR%\client.obj" "%BUILD_DIR%\dvdHook.obj" "%BUILD_DIR%\fsdDriver.obj" "%BUILD_DIR%\hooks.obj" ^
  "%BUILD_DIR%\irpCompare.obj" "%BUILD_DIR%\isoio.obj" "%BUILD_DIR%\main.obj" "%BUILD_DIR%\utility.obj" ^
  "%BUILD_DIR%\vtray.obj" || goto :fail

REM 4. Wrap the DLL into a devkit XEX with netiso's xex.xml (system DLL, base 0x91100000).
echo Creating XEX...
"%BINARYPATH%\imagexex.exe" /nologo /config:netiso\xex.xml /out:"%BUILD_DIR%\%OUTNAME%_devkit.xex" "%BUILD_DIR%\%OUTNAME%.dll" || goto :fail

REM 5. Retail conversion, as in the netiso.vcxproj post-build step.
where xextool >NUL 2>&1
if errorlevel 1 (
  copy /y "%BUILD_DIR%\%OUTNAME%_devkit.xex" "%OUTNAME%.xex" >NUL
  echo xextool not on PATH: %OUTNAME%.xex is the devkit image.
) else (
  xextool -m r -e d -r a -o "%OUTNAME%.xex" "%BUILD_DIR%\%OUTNAME%_devkit.xex" || goto :fail
)

echo Done: %~dp0%OUTNAME%.xex
popd
exit /b 0

:fail
echo Build failed.
popd
exit /b 1
