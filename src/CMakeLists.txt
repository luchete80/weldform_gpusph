#include_directories("${CMAKE_SOURCE_DIR}")
#include_directories("${CMAKE_SOURCE_DIR}/include")

set(CMAKE_CUDA_COMPILER "/usr/local/cuda-11.4/bin/nvcc")

project(gpusph LANGUAGES CXX CUDA)


find_package(CUDA  REQUIRED) #In order to find CUDA_INCLUDE_DIRS

include_directories(	${CUDA_INCLUDE_DIRS} 
			${CUDA_PATH}/include
			${PROJECT_SOURCE_DIR}
			${PROJECT_SOURCE_DIR}/cuda
			${PROJECT_SOURCE_DIR}/geometries
			${PROJECT_SOURCE_DIR}/integrators
			${PROJECT_SOURCE_DIR}/writers)

add_subdirectory(cuda)
add_subdirectory(geometries)

file(GLOB SOURCE
       #${PROJECT_SOURCE_DIR}/
			 *.cc			 
			 )


add_library (gpusph ${SOURCE})

target_link_libraries (gpusph geometries)	
			 
target_include_directories(gpusph PUBLIC
	${CUDA_INCLUDE_DIRS}
	
)
