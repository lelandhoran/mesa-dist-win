@TITLE Building Mesa3D

@rem Determine Mesa3D build environment root folder and convert the path to it into DOS 8.3 format to avoid quotes mess.
@cd "%~dp0"
@cd ..\..\
@for %%I in ("%cd%") do @set mesa=%%~sI

@rem Analyze environment. Get each dependency status: 0=missing, 1=standby, 2=loaded manually, 3=preloaded.
@rem Not all dependencies can have all these states.

@rem Search for Visual Studio environment. Hard fail if missing.
@set abi=x86
@set /p x64=Do you want to build for x64? (y/n) Otherwise build for x86:
@if /I "%x64%"=="y" set abi=x64
@set longabi=%abi%
@if %abi%==x64 set longabi=x86_64
@set vsabi=%abi%
@IF /I %PROCESSOR_ARCHITECTURE%==AMD64 IF %abi%==x86 set vsabi=x64_x86
@IF /I %PROCESSOR_ARCHITECTURE%==x86 IF %abi%==x64 set vsabi=x86_x64
@set vsenv="%ProgramFiles%
@IF /I %PROCESSOR_ARCHITECTURE%==AMD64 set vsenv=%vsenv% (x86)
@set vsenv=%vsenv%\Microsoft Visual Studio\2017\Community\VC\Auxiliary\Build\vcvarsall.bat"
@set toolset=0
@if EXIST %vsenv% set toolset=15
@if %toolset% EQU 0 (
@echo Error: No Visual Studio installed.
@GOTO exit
)
@set vsenv=%vsenv% %vsabi% %*
@TITLE Building Mesa3D %abi%

@rem Python. State restriction: cannot stay in standby since it is used everwhere. Hard fail if is missing.
@SET ERRORLEVEL=0
@SET pythonloc=python.exe
@set pythonstate=3
@where /q python.exe
@IF ERRORLEVEL 1 set pythonloc=%mesa%\python\python.exe
@IF %pythonloc%==%mesa%\python\python.exe set pythonstate=1
@IF %pythonstate%==1 IF NOT EXIST %pythonloc% set pythonstate=0
@IF %pythonstate%==3 FOR /F "tokens=* USEBACKQ" %%a IN (`where python.exe`) DO @SET pythonloc=%%a
@IF %pythonstate%==0 (
@echo Python is unreachable. Cannot continue.
@GOTO exit
)
@IF %pythonstate%==1 (
@SET PATH=%mesa%\python\;%PATH%
@SET pythonstate=2
)

@rem Identify Python version
@set pythonver=2
@IF EXIST "%pythonloc:python.exe=%python3.dll" set pythonver=3

@rem Look for python modules
@rem Mako - python 2 only
@set makoloc="%pythonloc:python.exe=%Lib\site-packages\mako"

@rem Meson - python 3 only
@SET mesonloc=meson.exe
@set mesonstate=3
@where /q meson.exe
@IF ERRORLEVEL 1 set mesonloc="%pythonloc:python.exe=%Scripts\meson.py"
@IF %mesonloc%=="%pythonloc:python.exe=%Scripts\meson.py" set mesonstate=2
@IF %mesonstate%==2 IF NOT EXIST %mesonloc% set mesonstate=0

@rem Scons - python 2 only
@set sconsloc="%pythonloc:python.exe=%Scripts\scons.py"

@rem Check for python updates
@set pyupd=n
@if %pythonver% GEQ 3 echo WARNING: Python 3.x support is experimental.
@if %pythonver% GEQ 3 echo.
@if %pythonver%==2 if NOT EXIST %makoloc% (
@python -m pip install -U setuptools
@python -m pip install -U pip
@python -m pip install -U scons
@python -m pip install -U MarkupSafe
@python -m pip install -U mako
@set pyupd=y
@echo.
)
@if %pythonver%==2 if NOT EXIST "%pythonloc:python.exe=%Lib\site-packages\win32" python -m pip install -U pypiwin32
@if %pythonver% GEQ 3 IF %mesonstate%==0 (
@python -m pip install -U setuptools
@python -m pip install -U pip
@python -m pip install -U meson
@set pyupd=y
@echo.
)
@if /I NOT "%pyupd%"=="y" set /p pyupd=Install/update python modules (y/n):
@if /I "%pyupd%"=="y" (
@for /F "delims= " %%i in ('python -m pip list -o --format=legacy') do @if NOT "%%i"=="pywin32" python -m pip install -U "%%i"
@echo.
)

@rem Ninja build system. This is optional
@SET ERRORLEVEL=0
@SET ninjaloc=ninja.exe
@set ninjastate=3
@where /q ninja.exe
@IF ERRORLEVEL 1 set ninjaloc=%mesa%\ninja\ninja.exe
@IF %ninjaloc%==%mesa%\ninja\ninja.exe set ninjastate=1
@IF %ninjastate%==1 IF NOT EXIST %ninjaloc% set ninjastate=0

@rem CMake build generator. Alterntive to Meson
@SET ERRORLEVEL=0
@SET cmakeloc=cmake.exe
@set cmakestate=3
@where /q cmake.exe
@IF ERRORLEVEL 1 set cmakeloc=%mesa%\cmake\bin\cmake.exe
@IF %cmakeloc%==%mesa%\cmake\bin\cmake.exe set cmakestate=1
@IF %cmakestate%==1 IF NOT EXIST %cmakeloc% set cmakestate=0

@rem Git version control
@SET ERRORLEVEL=0
@SET gitloc=git.exe
@set gitstate=3
@where /q git.exe
@IF ERRORLEVEL 1 set gitstate=0

@rem winflexbison
@SET ERRORLEVEL=0
@SET flexloc=win_flex.exe
@set flexstate=3
@where /q win_flex.exe
@IF ERRORLEVEL 1 set flexloc=%mesa%\flexbison\win_flex.exe
@IF %flexloc%==%mesa%\flexbison\win_flex.exe set flexstate=1
@IF %flexstate%==1 IF NOT EXIST %flexloc% set flexstate=0


:build_llvm
@if EXIST %mesa%\llvm set /p buildllvm=Begin LLVM build. Only needs to run once for each ABI and version. Proceed (y/n):
@if /I NOT "%buildllvm%"=="y" GOTO prep_mesa
@if EXIST %mesa%\llvm echo.
@cd %mesa%\llvm
@if EXIST %abi% RD /S /Q %abi%
@if EXIST cmake-%abi% RD /S /Q cmake-%abi%
@md cmake-%abi%
@cd cmake-%abi%
@set ninja=n
@set toolchain=Visual Studio %toolset%
@if EXIST "%ninjaloc%" set /p ninja=Use Ninja build system instead of MsBuild (y/n); less storage device strain and maybe faster build:
@if /I "%ninja%"=="y" set toolchain=Ninja
@if /I "%ninja%"=="y" set PATH=%mesa%\ninja\;%PATH%
@if %abi%==x64 set toolchain=%toolchain% Win64
@if "%toolchain%"=="Ninja Win64" set toolchain=Ninja
@if /I NOT "%ninja%"=="y" IF /I %PROCESSOR_ARCHITECTURE%==AMD64 set x64compiler= -Thost=x64
@set llvmbuildsys=%CD%
@if "%toolchain%"=="Ninja" call %vsenv%
@if "%toolchain%"=="Ninja" cd %llvmbuildsys%
@echo.
@IF %cmakestate%==1 set PATH=%mesa%\cmake\bin\;%PATH%
@cmake -G "%toolchain%"%x64compiler% -DLLVM_TARGETS_TO_BUILD=X86 -DCMAKE_BUILD_TYPE=Release -DLLVM_USE_CRT_RELEASE=MT -DLLVM_ENABLE_RTTI=1 -DLLVM_ENABLE_TERMINFO=OFF -DCMAKE_INSTALL_PREFIX=../%abi% ..
@echo.
@pause
@echo.
@if NOT "%toolchain%"=="Ninja" cmake --build . --config Release --target install
@if "%toolchain%"=="Ninja" ninja install
@echo.

:prep_mesa
@set PATH=%oldpath%
@cd %mesa%
@set mesapatched=0
@set haltmesabuild=n
@if %gitstate%==0 echo Error: Git not found. Auto-patching disabled.
@if NOT EXIST mesa if %gitstate%==0 echo Fatal: Both Mesa code and Git are missing. At least one is required. Execution halted.
@if NOT EXIST mesa if %gitstate%==0 GOTO distcreate
@if NOT EXIST mesa echo Warning: Mesa3D source code not found.
@if NOT EXIST mesa set /p haltmesabuild=Press Y to abort execution. Press any other key to download Mesa via Git:
@if /I "%haltmesabuild%"=="y" GOTO distcreate
@if NOT EXIST mesa set branch=master
@if NOT EXIST mesa set /p branch=Enter Mesa source code branch name - defaults to master:
@if NOT EXIST mesa echo.
@if NOT EXIST mesa git clone --recurse-submodules --depth=1 --branch=%branch% git://anongit.freedesktop.org/mesa/mesa mesa
@cd mesa
@set LLVM=%mesa%\llvm\%abi%
@rem set /p mesaver=<VERSION
@rem if "%mesaver:~-7%"=="0-devel" set /a intmesaver=%mesaver:~0,2%%mesaver:~3,1%00
@rem if "%mesaver:~5,4%"=="0-rc" set /a intmesaver=%mesaver:~0,2%%mesaver:~3,1%00+%mesaver:~9%
@rem if NOT "%mesaver:~5,2%"=="0-" set /a intmesaver=%mesaver:~0,2%%mesaver:~3,1%50+%mesaver:~5%
@if EXIST mesapatched.ini GOTO build_mesa
@if %gitstate%==0 GOTO build_mesa
@git apply -v ..\mesa-dist-win\patches\s3tc.patch
@set mesapatched=1
@echo %mesapatched% > mesapatched.ini
@echo.

:build_mesa
@set /p buildmesa=Begin mesa build. Proceed (y/n):
@if /i NOT "%buildmesa%"=="y" GOTO distcreate
@echo.
@cd %mesa%\mesa
@set sconscmd=python %sconsloc% build=release platform=windows machine=%longabi% libgl-gdi
@set llvmless=n
@if EXIST %LLVM% set /p llvmless=Build Mesa without LLVM (y/n). Only softpipe and osmesa will be available:
@if EXIST %LLVM% echo.
@if NOT EXIST %LLVM% set /p llvmless=Build Mesa without LLVM (y=yes/n=quit). Only softpipe and osmesa will be available:
@if NOT EXIST %LLVM% echo.
@if /I "%llvmless%"=="y" set sconscmd=%sconscmd% llvm=no
@if /I "%llvmless%"=="y" GOTO osmesa
@if /I NOT "%llvmless%"=="y" if NOT EXIST %LLVM% GOTO distcreate
@set swrdrv=n
@if %abi%==x64 set /p swrdrv=Do you want to build swr drivers? (y=yes):
@if %abi%==x64 echo.
@if /I "%swrdrv%"=="y" set sconscmd=%sconscmd% swr=1
@set /p graw=Do you want to build graw library (y/n):
@echo.
@if /I "%graw%"=="y" set sconscmd=%sconscmd% graw-gdi

:osmesa
@set /p osmesa=Do you want to build off-screen rendering drivers (y/n):
@echo.
@if /I "%osmesa%"=="y" set sconscmd=%sconscmd% osmesa

:build_mesa_exec
@IF %flexstate%==1 set PATH=%mesa%\flexbison\;%PATH%
@cd %mesa%\mesa
@set cleanbuild=n
@if EXIST build\windows-%longabi% set /p cleanbuild=Do you want to clean build (y/n):
@if EXIST build\windows-%longabi% echo.
@if /I "%cleanbuild%"=="y" RD /S /Q build\windows-%longabi%
@if NOT EXIST build md build
@if NOT EXIST build\windows-%longabi% md build\windows-%longabi%
@if NOT EXIST build\windows-%longabi%\git_sha1.h echo 0 > build\windows-%longabi%\git_sha1.h
@echo.
@%sconscmd%
@echo.

:distcreate
@if NOT EXIST %mesa%\mesa\build\windows-%longabi% GOTO exit
@set /p dist=Create or update Mesa3D distribution package (y/n):
@echo.
@if /I NOT "%dist%"=="y" GOTO exit
@cd %mesa%
@if NOT EXIST mesa-dist-win MD mesa-dist-win
@cd mesa-dist-win
@if NOT EXIST bin MD bin
@cd bin
@if EXIST %abi% RD /S /Q %abi%
@MD %abi%
@cd %abi%
@MD osmesa-gallium
@MD osmesa-swrast
@copy %mesa%\mesa\build\windows-%longabi%\gallium\targets\libgl-gdi\opengl32.dll opengl32.dll
@if %abi%==x64 copy %mesa%\mesa\build\windows-%longabi%\gallium\drivers\swr\swrAVX.dll swrAVX.dll
@if %abi%==x64 copy %mesa%\mesa\build\windows-%longabi%\gallium\drivers\swr\swrAVX2.dll swrAVX2.dll
@copy %mesa%\mesa\build\windows-%longabi%\mesa\drivers\osmesa\osmesa.dll osmesa-swrast\osmesa.dll
@copy %mesa%\mesa\build\windows-%longabi%\gallium\targets\osmesa\osmesa.dll osmesa-gallium\osmesa.dll
@copy %mesa%\mesa\build\windows-%longabi%\gallium\targets\graw-gdi\graw.dll graw.dll
@echo.

:exit
@pause
@exit