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
 * This file is only used to hold the actual strings
 * defining the buffer printable names.
 */

#include <stdexcept>
#include <string>

#include "GlobalData.h"

// re-include define-buffers to set the printable name
#undef DEFINED_BUFFERS
#undef SET_BUFFER_TRAITS
#define SET_BUFFER_TRAITS(code, _type, _nbufs, _name) \
const char BufferTraits<code>::name[] = _name
#include "define_buffers.h"
#undef SET_BUFFER_TRAITS


using namespace std;

const char * getBufferName(flag_t key)
{
#undef DEFINED_BUFFERS
#define SET_BUFFER_TRAITS(code, _type, _nbufs, _name) \
	case code: return BufferTraits<code>::name;

	/* Reinclude the buffer definitions to build a switch table
	 * for the buffer names
	 */
	switch (key) {
#include "define_buffers.h"
	default:
		throw invalid_argument("unknown Buffer key " + to_string(key));
	}

#undef SET_BUFFER_TRAITS
}
