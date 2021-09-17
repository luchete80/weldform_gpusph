/*  Copyright (c) 2011-2019 INGV, EDF, UniCT, JHU

    Istituto Nazionale di Geofisica e Vulcanologia, Sezione di Catania, Italy
    Électricité de France, Paris, France
    Università di Catania, Catania, Italy
    Johns Hopkins University, Baltimore (MD), USA

    This file is part of GPUSPH. Project founders:
        Alexis Hérault, Giuseppe Bilotta, Robert A. Dalrymple,
        Eugenio Rustico, Ciro Del Negro
    For a full list of authors and project partners, consult the logs
    and the project website <https://www.gpusph.org>

    GPUSPH is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    GPUSPH is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with GPUSPH.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <iostream>

#include "ProblemExample.h"
/*#include "Cube.h"
#include "Point.h"
#include "Vector.h"
#include "GlobalData.h"*/
#include "cudasimframework.cu"

ProblemExample::ProblemExample(GlobalData *_gdata) : Problem(_gdata)
{
	SETUP_FRAMEWORK(
		// TODO update from legacy viscous models
		// laminar viscosity type: KINEMATICVISC, DYNAMICVISC
		// turbulent viscosity type: ARTVISC, SPSVISC, KEPSVISC
		viscosity<ARTVISC>,
		// boundary types: LJ_BOUNDARY, MK_BOUNDARY, SA_BOUNDARY, DYN_BOUNDARY
		boundary<LJ_BOUNDARY>,
		add_flags<ENABLE_PLANES>
	);

	// *** Initialization of minimal physical parameters
	set_deltap(0.02f);
	set_gravity(-9.81);
	setMaxFall(3.0);
	float g = get_gravity_magnitude();
	add_fluid(1000.0);
	set_equation_of_state(0,  7.0f, 20.0f);
	//set_kinematic_visc(0, 1.0e-2f);

	// *** Initialization of minimal simulation parameters
	resize_neiblist(256, 32);

	// *** Other parameters and settings
	add_writer(VTKWRITER, 1e-1f);
	m_name = "ProblemExample";

	// *** Post-processing
	// In our case we show an example of how to add the problem-specific
	// CALC_PRIVATE post-processing. Additional post-processing functions
	// are defined in PostProcessType
	addPostProcess(CALC_PRIVATE);

	// domain size
	const double dimX = 10;
	const double dimY = 10;
	const double dimZ = 3;

	// world size
	m_origin = make_double3(0, 0, 0);
	// NOTE: NAN value means that will be computed automatically
	m_size = make_double3(dimX, dimY, dimZ);

	// size and height of grid of cubes
	const double cube_size = 0.4;
	const double cube_Z = 1;

	// size and height of spheres of water
	const double sphere_radius = 0.5;
	const double sphere_Z = 2;

	// will create a grid of cubes and spheres
	const double grid_size = dimX / 5;
	const uint cubes_grid_size = 4;
	const uint spheres_grid_size = 3;

	// every geometry will be centered in the given coordinate
	setPositioning(PP_CENTER);

	// create infinite floor
	addPlane(0, 0, 1, 0);

	// origin of the grid of cubes and spheres
	const double cornerXY = (dimX / 2) - (grid_size / 2);

	// grid of cubes
	for (uint i=0; i < cubes_grid_size; i++)
		for (uint j=0; j < cubes_grid_size; j++) {
			// create cube
			GeometryID current = addCube(GT_FIXED_BOUNDARY, FT_BORDER,
				Point( cornerXY + i*grid_size/(cubes_grid_size-1),
				cornerXY + j*grid_size/(cubes_grid_size-1), cube_Z), cube_size);
			// rotate it
			rotate(current, i * (M_PI/2) / cubes_grid_size, j * (M_PI/2) / cubes_grid_size, 0);
		}

	// grid of spheres
	for (uint i=0; i < spheres_grid_size; i++)
		for (uint j=0; j < spheres_grid_size; j++)
			addSphere(GT_FLUID, FT_SOLID,
				Point( cornerXY + i*grid_size/(spheres_grid_size-1),
				cornerXY + j*grid_size/(spheres_grid_size-1), sphere_Z), sphere_radius);

	// setMassByDensity(floating_obj, physparams()->rho0[0] / 2);
}

using namespace cubounds; // to access calcGridPosFromParticleHash in device code
using namespace cuneibs; // to access iterators over neighbors

//! Compute a private variable
/*!
 This function computes an arbitrary passive array. It can be used for
 debugging purposes or passive scalars.

 In this example we simply compute the number of neighbors.
 */
template<BoundaryType boundarytype>
__global__ void
calcPrivateDevice(
			float*		priv,
	const	float4*		__restrict__	posArray,
	const	float4*		__restrict__		velArray,
	const	particleinfo* __restrict__	infoArray,
	const	hashKey*	__restrict__	particleHash,
	const	uint*		__restrict__	cellStart,
	const	neibdata*	__restrict__	neibsList,
	const	float		slength,
	const	float		inflRadius,
			uint		numParticles)
{
	const uint index = INTMUL(blockIdx.x,blockDim.x) + threadIdx.x;

	if (index >= numParticles)
		return;

	const float4 pos = posArray[index];
	// To access the particle info and e.g. filter action based on particle type:
	//const particleinfo info = infoArray[index];
	// To access the particle velocity and density, e.g. to apply the standard SPH smoothing
	//const float4 vel = velArray[index];

	const int3 gridPos = calcGridPosFromParticleHash( particleHash[index] );

	uint neibs = 0;

	// Loop over all the neighbors
	for_every_neib(boundarytype, index, pos, gridPos, cellStart, neibsList) {

		const uint neib_index = neib_iter.neib_index();

		// Compute relative position vector and distance
		// Now relPos is a float4 and neib mass is stored in relPos.w
		const float4 relPos = neib_iter.relPos(posArray[neib_index]);

		float r = length3(relPos);
		if (r < inflRadius)
			neibs += 1;
	}

	// Will convert to float on storage, because BUFFER_PRIVATE is a float buffer
	priv[index] = neibs;
}

void ProblemExample::calcPrivate(flag_t options,
	BufferList const& bufread,
	BufferList & bufwrite,
	uint numParticles,
	uint particleRangeEnd,
	uint deviceIndex,
	const GlobalData * const gdata)
{
	/* Example of typical implementation */

	// thread per particle
	uint numThreads = BLOCK_SIZE_CALCTEST;
	uint numBlocks = div_up(particleRangeEnd, numThreads);

	const float4 *pos = bufread.getData<BUFFER_POS>();
	const float4 *vel = bufread.getData<BUFFER_VEL>();
	const particleinfo *info = bufread.getData<BUFFER_INFO>();
	const hashKey *particleHash = bufread.getData<BUFFER_HASH>();
	const uint *cellStart = bufread.getData<BUFFER_CELLSTART>();
	const neibdata *neibsList = bufread.getData<BUFFER_NEIBSLIST>();

	float *priv = bufwrite.getData<BUFFER_PRIVATE>();

	//execute kernel
	calcPrivateDevice<LJ_BOUNDARY><<<numBlocks, numThreads>>>(
			priv,
			pos, vel, info,
			particleHash,
			cellStart,
			neibsList,
			simparams()->slength,
			simparams()->influenceRadius,
			numParticles);

	KERNEL_CHECK_ERROR;
}

std::string
ProblemExample::get_private_name(flag_t buffer) const
{
	return "NeibsNum";
}
