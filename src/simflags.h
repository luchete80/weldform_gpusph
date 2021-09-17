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

/*! \file
 * Set of boolean aspects of the simulation, to determine if
 * any of the features is enabled (XSPH, adaptive timestep, moving
 * boundaries, inlet/outlet, DEM, etc)
 */

/* \note
 * simflags.h is scanned by the SALOME user interface.
 * To change the user interface, it is only necessary to
 * modify the appropriate comments in simparams.h, physparams.h,
 * Problem.h, XProblem.h, particledefine.h and simflags.h
 * The variable labels and tooltips are
 * defined in the user interface files themselves, so
 * ease follow the convention we adopted: use placeholders
 * in the GPUSPH files and define them in GPUSPHGUI.
 * The tooltips are the comments appearing when sliding
 * the mouse over a variable in the interface. They are
 * contained in the TLT_ variables. All the placeholders
 * contents are defined in:
 * gpusphgui/SGPUSPH_SRC/src/SGPUSPHGUI/resources/SGPUSPH_msg_en.ts
 * The sections to be used in the user interface are
 * defined in gpusphgui/SGPUSPH/resources/params.xml.
 * To assign a parameter to a section, the command
 * \inpsection is used.
 * Please consult this file for the list of sections.
 */


#ifndef _SIMFLAGS_H
#define _SIMFLAGS_H

#include "common_types.h"

//! No options
#define ENABLE_NONE				0UL

//! Adaptive timestepping
/**@defpsubsection{variable_dt, ENABLE_DTADAPT}
 * @inpsection{time}
 * @default{enable}
 * @values{disable,enable}
 * TLT_ENABLE_DTADAPT
 */
#define ENABLE_DTADAPT			1UL

//! XSPH
/**@defpsubsection{xsph, ENABLE_XSPH}
 * @inpsection{density_calculation}
 * @default{disable}
 * @values{disable,enable}
 * TLT_ENABLE_XSPH
 */
#define ENABLE_XSPH				(ENABLE_DTADAPT << 1)

//! planes
#define ENABLE_PLANES			(ENABLE_XSPH << 1)

//! DEM
#define ENABLE_DEM				(ENABLE_PLANES << 1)

//! moving boundaries and rigid bodies
#define ENABLE_MOVING_BODIES	(ENABLE_DEM << 1)

//! inlet/outlet
//! open boundaries
#define ENABLE_INLET_OUTLET		(ENABLE_MOVING_BODIES << 1)

//! water depth computation
/**@defpsubsection{compute_water_level, ENABLE_WATER_DEPTH}
 * @inpsection{boundaries}
 * @default{disable}
 * @values{disable,enable}
 * TLT_ENABLE_WATER_DEPTH
 */
#define ENABLE_WATER_DEPTH		(ENABLE_INLET_OUTLET << 1)

//! Summation density
/**@defpsubsection{density_sum, ENABLE_DENSITY_SUM}
 * @inpsection{density_calculation}
 * @default{enable}
 * @values{disable,enable}
 * TLT_ENABLE_DENSITY_SUM
 */
#define ENABLE_DENSITY_SUM		(ENABLE_WATER_DEPTH << 1)

//! Compute gamma through Gauss quadrature formula. This is
//! alternative to the dynamic gamma computation
//! (gamma computed from an advection equation)
//! used by default.
/**@defpsubsection{gamma_quadrature, ENABLE_GAMMA_QUADRATURE}
 * @inpsection{boundaries}
 * @default{disable}
 * @values{disable,enable}
 * TLT_ENABLE_GAMMA_QUADRATURE
 */
#define ENABLE_GAMMA_QUADRATURE		(ENABLE_DENSITY_SUM << 1)
#define USING_DYNAMIC_GAMMA(flags)	(!((flags) & ENABLE_GAMMA_QUADRATURE))

//! repacking
/**@defpsubsection{repacking, ENABLE_REPACKING}
 * @inpsection{initialisation}
 * @default{disable}
 * @values{disable,enable}
 * TLT_ENABLE_REPACKING
 */
#define ENABLE_REPACKING		(ENABLE_GAMMA_QUADRATURE << 1)

//! Compute internal energy
/**@defpsubsection{internal_energy, ENABLE_INTERNAL_ENERGY}
 * @inpsection{output}
 * @default{disable}
 * @values{disable,enable}
 * TLT_ENABLE_INTERNAL_ENERGY
 */
#define ENABLE_INTERNAL_ENERGY (ENABLE_REPACKING<< 1)

//! Enable multi-fluid support
/*! This disables optimizations in the viscous contributions that assume
 * a single constant viscosity for all particles
 */
#define ENABLE_MULTIFLUID	(ENABLE_INTERNAL_ENERGY <<1)
#define IS_MULTIFLUID(flags)	((flags) & ENABLE_MULTIFLUID)
#define IS_SINGLEFLUID(flags)	(!IS_MULTIFLUID(flags))

//! Last simulation flag
#define LAST_SIMFLAG		ENABLE_MULTIFLUID

//! All flags.
//! Since flags are a bitmap, LAST_SIMFLAG - 1 sets all bits before
//! the LAST_SIMFLAG bit, and OR-ing with LAST_SIMFLAG gives us
//! all flags. This is slightly safer than using ((LAST_SIMFLAG << 1) - 1)
//! in case LAST_SIMFLAG is already the last bit
#define ENABLE_ALL_SIMFLAGS		(LAST_SIMFLAG | (LAST_SIMFLAG-1))

/// General query that identifies whether the flags in field are set, true only if all of them are
#define QUERY_ALL_FLAGS(field, flags)	(((field) & (flags)) == (flags))
/// General query that identifies whether at least one flag in field is set
#define QUERY_ANY_FLAGS(field, flags)	((field) & (flags))

/// Disable individual flags in a given field
#define DISABLE_FLAGS(field, flags) ((field) & ~(flags))

/// The flags enabled by default
#define DEFAULT_FLAGS ENABLE_DTADAPT

#endif
