file(GLOB CUDA_SOURCES
       #${PROJECT_SOURCE_DIR}/
			 *.cu			 
			 )


add_library (cuda ${CUDA_SOURCES})
