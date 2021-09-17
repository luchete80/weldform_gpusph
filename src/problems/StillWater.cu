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

#include "StillWater.h"
#include "GlobalData.h"
#include "cudasimframework.cu"

#define CENTER_DOMAIN 0
// set to coords (x,y,z) if more accuracy is needed in such point
// (waiting for relative coordinates)
#if CENTER_DOMAIN
#define OFFSET_X (-l/2)
#define OFFSET_Y (-w/2)
#define OFFSET_Z (-h/2)
#else
#define OFFSET_X 0
#define OFFSET_Y 0
#define OFFSET_Z 0
#endif

StillWater::StillWater(GlobalData *_gdata) : Problem(_gdata)
{
	m_usePlanes = get_option("use-planes", false); // --use-planes true to enable use of planes for boundaries
	const int mlsIters = get_option("mls", 0); // --mls N to enable MLS filter every N iterations
	const int ppH = get_option("ppH", 16); // --ppH N to change deltap to H/N

	// density diffusion terms, see DensityDiffusionType
	const DensityDiffusionType rhodiff = get_option("density-diffusion", FERRARI);

	SETUP_FRAMEWORK(
		//viscosity<KINEMATICVISC>,
		viscosity<DYNAMICVISC>,
		//viscosity<ARTVISC>,
		boundary<DYN_BOUNDARY>
		//boundary<LJ_BOUNDARY>
	).select_options(
		rhodiff,
		m_usePlanes, add_flags<ENABLE_PLANES>()
	);

	if (mlsIters > 0)
		addFilter(MLS_FILTER, mlsIters);

	H = 1;

	set_deltap(H/ppH);

	setMaxFall(H);

	l = w = sqrt(2)*H; h = 1.1*H;

	// Size and origin of the simulation domain
	m_size = make_double3(l, w ,h);
	m_origin = make_double3(OFFSET_X, OFFSET_Y, OFFSET_Z);

	// SPH parameters
	set_timestep(0.00004f);
	simparams()->dtadaptfactor = 0.3;
	simparams()->buildneibsfreq = 20;
	simparams()->ferrariLengthScale = H;

	// enlarge the domain to take into account the extra layers of particles
	// of the boundary
	if (simparams()->boundarytype == DYN_BOUNDARY && !m_usePlanes) {
		// number of layers
		dyn_layers = ceil(simparams()->kernelradius*simparams()->sfactor);
		// extra layers are one less (since other boundary types still have
		// one layer)
		double3 extra_offset = make_double3((dyn_layers-1)*m_deltap);
		m_origin -= extra_offset;
		m_size += 2*extra_offset;
	} else {
		dyn_layers = 1;
	}

	simparams()->tend = 100.0;
	if (simparams()->boundarytype == SA_BOUNDARY) {
		resize_neiblist(128, 128);
	};

	// Physical parameters
	set_gravity(-9.81f);
	const float g = get_gravity_magnitude();
	const float maxvel = sqrt(2*g*H);
	// purely for cosmetic reason, let's round the soundspeed to the next
	// integer
	const float c0 = ceil(10*maxvel);
	add_fluid(1000.0);
	set_equation_of_state(0, 7.0f, c0);

	//physparams()->visccoeff = 0.05f;
	set_kinematic_visc(0, 3.0e-2f);
	//set_kinematic_visc(0, 1.0e-6f);

	// Drawing and saving times
	add_writer(VTKWRITER, 1.0);

	// Name of problem used for directory creation
	m_name = "StillWater";

	// Building the geometry
	setPositioning(PP_CORNER);
	// distance between fluid box and wall
	float wd = m_deltap;

	GeometryID experiment_box = addBox(GT_FIXED_BOUNDARY, FT_BORDER,
		Point(m_origin), m_size.x, m_size.y, m_size.z);
	disableCollisions(experiment_box);

	m_fluidOrigin = m_origin;
	if (dyn_layers > 1) // shift by the extra offset of the experiment box
		m_fluidOrigin += make_double3((dyn_layers)*m_deltap);
	m_fluidOrigin += make_double3(wd); // one wd space from the boundary
	double shift = 2*wd;
	if (dyn_layers > 1)
		shift = (dyn_layers-1)*m_deltap*2;
	GeometryID fluid = addBox(GT_FLUID, FT_SOLID,
		m_fluidOrigin, l-shift, w-shift, H-shift);

}

void StillWater::copy_planes(PlaneList& planes)
{
	if (!m_usePlanes) return;

	planes.push_back( implicit_plane(0, 0, 1.0, -m_origin.z) );
	planes.push_back( implicit_plane(0, 1.0, 0, -m_origin.x) );
	planes.push_back( implicit_plane(0, -1.0, 0, m_origin.x + w) );
	planes.push_back( implicit_plane(1.0, 0, 0, -m_origin.y) );
	planes.push_back( implicit_plane(-1.0, 0, 0, m_origin.y + l) );
}

