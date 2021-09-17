file(GLOB SOURCE
       #${PROJECT_SOURCE_DIR}/
			 *.cu			 
			 )


add_library (geometries ${SOURCE})
