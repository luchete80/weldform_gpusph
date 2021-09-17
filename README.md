"C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"

export CUDA_PATH=/usr/local/cuda-11.4
set CUDA_PATH="C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.2"

cmake ..\gpusph -G "NMake Makefiles" -DCMAKE_CUDA_COMPILER="C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v11.2/bin/nvcc.exe"
