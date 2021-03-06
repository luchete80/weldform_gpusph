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

#include "Compression.h"
#include "Cube.h"
#include "Point.h"
#include "Vector.h"
#include "GlobalData.h"
#include "cudasimframework.cu"

Compression::Compression(GlobalData *_gdata) : Problem(_gdata)
{
	// *** user parameters from command line
	const bool WET = get_option("wet", false);
	const bool USE_PLANES = get_option("use_planes", false);
	const uint NUM_OBSTACLES = get_option("num_obstacles", 1);
	const bool ROTATE_OBSTACLE = get_option("rotate_obstacle", true);
	const uint NUM_TESTPOINTS = get_option("num_testpoints", 3);
	// density diffusion terms: 0 none, 1 Ferrari, 2 Molteni & Colagrossi, 3 Brezzi
	const DensityDiffusionType RHODIFF = get_option("density-diffusion", COLAGROSSI);

	// ** framework setup
	// viscosities: KINEMATICVISC*, DYNAMICVISC*
	// turbulence models: ARTVISC*, SPSVISC, KEPSVISC
	// boundary types: LJ_BOUNDARY*, MK_BOUNDARY, SA_BOUNDARY, DYN_BOUNDARY*
	// * = tested in this problem
	SETUP_FRAMEWORK(
		viscosity<ARTVISC>,
		boundary<DYN_BOUNDARY>,
		add_flags<ENABLE_REPACKING>
	).select_options(
		RHODIFF,
		USE_PLANES, add_flags<ENABLE_PLANES>()
	);

	// will dump testpoints separately
	addPostProcess(TESTPOINTS);

	// Allow user to set the MLS frequency at runtime. Default to 0 if density
	// diffusion is enabled, 10 otherwise
	const int mlsIters = get_option("mls",
		(simparams()->densitydiffusiontype != DENSITY_DIFFUSION_NONE) ? 0 : 10);

	if (mlsIters > 0)
		addFilter(MLS_FILTER, mlsIters);

	// Explicitly set number of layers. Also, prevent having undefined number of layers before the constructor ends.
	setDynamicBoundariesLayers(3);

	resize_neiblist(128);

	// *** Initialization of minimal physical parameters
	set_deltap(0.015f);
	//set_timestep(0.00005);
	set_gravity(-9.81);
	const float g = get_gravity_magnitude();
	const double H = 0.4;
	setMaxFall(H);
	add_fluid(2700.0);

	//add_fluid(2350.0);
	set_equation_of_state(0,  7.0f, 20.0f);
	set_kinematic_visc(0, 1.0e-2f);
	//set_dynamic_visc(0, 1.0e-4f);

	// default tend 1.5s
	simparams()->tend=1.5f;
	//simparams()->ferrariLengthScale = H;
	simparams()->densityDiffCoeff = 0.1f;
	/*set_artificial_visc(0.2f);
	set_sps_parameters(0.12, 0.0066); // default values
	physparams()->epsartvisc = 0.01*simparams()->slength*simparams()->slength;*/
	simparams()->repack_a = 0.1f;
	simparams()->repack_alpha = 0.01f;
	simparams()->repack_maxiter = 10;

	// Drawing and saving times
	add_writer(VTKWRITER, 0.005f);
	//addPostProcess(VORTICITY);
	// *** Other parameters and settings
	m_name = "Compression";

	// *** Geometrical parameters, starting from the size of the domain
	const double dimX = 1.6;
	const double dimY = 0.67;
	const double dimZ = 0.6;
	const double obstacle_side = 0.12;
	const double obstacle_xpos = 0.9;
	const double water_length = 0.4;
	const double water_height = H;
	const double water_bed_height = 0.1;

	// If we used only makeUniverseBox(), origin and size would be computed automatically
	m_origin = make_double3(0, 0, 0);
	m_size = make_double3(dimX, dimY, dimZ);

	// set positioning policy to PP_CORNER: given point will be the corner of the geometry
	setPositioning(PP_CORNER);

	// main container
	if (USE_PLANES) {
		// limit domain with 6 planes
		makeUniverseBox(m_origin, m_origin + m_size);
	} else {
		GeometryID box =
			addBox(GT_FIXED_BOUNDARY, FT_BORDER, m_origin, dimX, dimY, dimZ);
		// we simulate inside the box, so do not erase anything
		setEraseOperation(box, ET_ERASE_NOTHING);
	}

	// Planes unfill automatically but the box won't, to void deleting all the water. Thus,
	// we define the water at already the right distance from the walls.
	double BOUNDARY_DISTANCE = m_deltap;
	if (simparams()->boundarytype == DYN_BOUNDARY && !USE_PLANES)
			BOUNDARY_DISTANCE *= getDynamicBoundariesLayers();

	// Add the main water part
	addBox(GT_FLUID, FT_SOLID, Point(BOUNDARY_DISTANCE, BOUNDARY_DISTANCE, BOUNDARY_DISTANCE),
		water_length - BOUNDARY_DISTANCE, dimY - 2 * BOUNDARY_DISTANCE, water_height - BOUNDARY_DISTANCE);
	// Add the water bed if wet. After we'll implement the unfill with custom dx, it will be possible to declare
	// the water bed overlapping with the main part.
	if (WET) {
		addBox(GT_FLUID, FT_SOLID,
			Point(water_length + m_deltap, BOUNDARY_DISTANCE, BOUNDARY_DISTANCE),
			dimX - water_length - BOUNDARY_DISTANCE - m_deltap,
			dimY - 2 * BOUNDARY_DISTANCE,
			water_bed_height - BOUNDARY_DISTANCE);
	}

	// set positioning policy to PP_BOTTOM_CENTER: given point will be the center of the base
	setPositioning(PP_BOTTOM_CENTER);

	// add one or more obstacles
	const double Y_DISTANCE = dimY / (NUM_OBSTACLES + 1);
	// rotation angle
	const double Z_ANGLE = M_PI / 4;

	// add testpoints
	const float TESTPOINT_DISTANCE = dimZ / (NUM_TESTPOINTS + 1);
	for (uint t = 0; t < NUM_TESTPOINTS; t++)
		addTestPoint(Point(0.25*dimX, dimY/2.0, (t+1) * TESTPOINT_DISTANCE/2.0));

	for (uint t = 0; t < NUM_TESTPOINTS; t++)
		addTestPoint(Point(0.4*dimX, dimY/2.0, (t+1) * TESTPOINT_DISTANCE/2.0));

	for (uint t = 0; t < NUM_TESTPOINTS; t++)
		addTestPoint(Point(0.75*dimX, dimY/2.0, (t+1) * TESTPOINT_DISTANCE/2.0));

	for (uint t = 0; t < NUM_TESTPOINTS; t++)
		addTestPoint(Point(0.9*dimX, dimY/2.0, (t+1) * TESTPOINT_DISTANCE/2.0));
}

// since the fluid topology is roughly symmetric along Y through the whole simulation, prefer Y split
void Compression::fillDeviceMap()
{
	fillDeviceMapByAxis(Y_AXIS);
}

/*
bool Compression::need_write(double t) const
{
 	return 0;
}
*/


